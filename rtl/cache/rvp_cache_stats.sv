/**
 * rvp_cache_stats.sv - Cache Hit-Rate Statistics Module
 *
 * Counts cache accesses, hits, misses, evictions and (for D-Cache) dirty
 * evictions and write accesses. Exposes the running totals as a packed
 * struct so the SoC can read them via a memory-mapped register file or a
 * CSR.
 *
 * The counters are sized to 32 bits. At a 100 MHz clock and a worst-case
 * access every cycle, the counters wrap in ~42 seconds - sufficient for
 * benchmark runs of typical course projects. For longer runs, provide a
 * sample-and-clear handshake (TODO).
 *
 * Reference: ibex_counter.sv (basic 32-bit saturating counter pattern).
 */

module rvp_cache_stats
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  // 1 = enable counting (parameterized so unused stats instances can be
  // stripped to save area in non-analysis builds).
  parameter bit STATS_ENABLE = 1'b1
) (
  input  logic          clk_i,
  input  logic          rst_ni,

  // --------------------------------------------------------------------------
  // Event inputs (all one-cycle pulses, except access_i which is level)
  // --------------------------------------------------------------------------
  input  logic          access_i,        // 1 = a cache access occurred this cycle
  input  logic          hit_i,           // 1 = access was a hit
  input  logic          miss_i,          // 1 = access was a miss
  input  logic          eviction_i,      // 1 = a line was evicted
  input  logic          dirty_evict_i,   //1 = evicted line was dirty (D-Cache only)
  input  logic          read_i,          // 1 = access was a read
  input  logic          write_i,         // 1 = access was a write (D-Cache only)

  // --------------------------------------------------------------------------
  // Snapshot output (continuously updated)
  // --------------------------------------------------------------------------
  output cache_stats_t  stats_o,

  // --------------------------------------------------------------------------
  // Control interface (optional - for CSR-driven snapshot/clear)
  // --------------------------------------------------------------------------
  input  logic          clear_i,         // 1 = reset all counters to zero
  input  logic          sample_i        // 1 = latch current counters to a
                                        //     shadow register (TODO)
);

  // --------------------------------------------------------------------------
  // Counter storage
  // --------------------------------------------------------------------------
  logic [31:0] total_accesses_q;
  logic [31:0] cache_hits_q;
  logic [31:0] cache_misses_q;
  logic [31:0] evictions_q;
  logic [31:0] dirty_evictions_q;
  logic [31:0] read_accesses_q;
  logic [31:0] write_accesses_q;

  // --------------------------------------------------------------------------
  // Counter update logic
  // --------------------------------------------------------------------------
  // Each counter is a simple 32-bit saturating incrementer. Saturate at
  // 32'hFFFFFFFF to avoid wraparound misleading the analysis.
  //
  // TODO: provide a non-saturating wrap option if the host software is
  //       prepared to handle overflow.

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      total_accesses_q    <= '0;
      cache_hits_q        <= '0;
      cache_misses_q      <= '0;
      evictions_q         <= '0;
      dirty_evictions_q   <= '0;
      read_accesses_q     <= '0;
      write_accesses_q    <= '0;
    end else if (clear_i) begin
      // Synchronous clear (CSR-driven reset of stats window)
      total_accesses_q    <= '0;
      cache_hits_q        <= '0;
      cache_misses_q      <= '0;
      evictions_q         <= '0;
      dirty_evictions_q   <= '0;
      read_accesses_q     <= '0;
      write_accesses_q    <= '0;
    end else if (STATS_ENABLE) begin
      // Total accesses
      if (access_i && total_accesses_q != 32'hFFFFFFFF) begin
        total_accesses_q <= total_accesses_q + 1'b1;
      end
      // Hits
      if (hit_i && cache_hits_q != 32'hFFFFFFFF) begin
        cache_hits_q <= cache_hits_q + 1'b1;
      end
      // Misses
      if (miss_i && cache_misses_q != 32'hFFFFFFFF) begin
        cache_misses_q <= cache_misses_q + 1'b1;
      end
      // Evictions
      if (eviction_i && evictions_q != 32'hFFFFFFFF) begin
        evictions_q <= evictions_q + 1'b1;
      end
      // Dirty evictions (subset of evictions, counted separately for writeback
      // bandwidth analysis)
      if (dirty_evict_i && dirty_evictions_q != 32'hFFFFFFFF) begin
        dirty_evictions_q <= dirty_evictions_q + 1'b1;
      end
      // Read accesses
      if (read_i && read_accesses_q != 32'hFFFFFFFF) begin
        read_accesses_q <= read_accesses_q + 1'b1;
      end
      // Write accesses
      if (write_i && write_accesses_q != 32'hFFFFFFFF) begin
        write_accesses_q <= write_accesses_q + 1'b1;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Output struct
  // --------------------------------------------------------------------------
  assign stats_o.total_accesses  = total_accesses_q;
  assign stats_o.cache_hits      = cache_hits_q;
  assign stats_o.cache_misses    = cache_misses_q;
  assign stats_o.evictions       = evictions_q;
  assign stats_o.dirty_evictions = dirty_evictions_q;
  assign stats_o.read_accesses   = read_accesses_q;
  assign stats_o.write_accesses  = write_accesses_q;

  // --------------------------------------------------------------------------
  // TODO: Snapshot register
  // --------------------------------------------------------------------------
  // Implement a shadow register that latches the current counter values when
  // sample_i is asserted. This lets software read a consistent snapshot of
  // all counters atomically (otherwise counters may advance between
  // individual CSR reads, giving inconsistent totals).
  //
  // Suggested implementation:
  //   cache_stats_t snapshot_q;
  //   always_ff @(posedge clk_i or negedge rst_ni) begin
  //     if (!rst_ni)            snapshot_q <= '0;
  //     else if (sample_i)      snapshot_q <= stats_o;
  //   end
  //   output snapshot_o -> CSR file

  // --------------------------------------------------------------------------
  // TODO: Derived metrics in hardware
  // --------------------------------------------------------------------------
  // - hit rate (computed via calc_hit_rate function in rvp_cache_pkg)
  // - miss rate
  // - average memory access time (AMAT):
  //     AMAT = hit_time + miss_rate * miss_penalty
  //   These can be computed in software from the raw counters; providing them
  //   in hardware is optional and only useful for real-time displays.

  // --------------------------------------------------------------------------
  // Assertions
  // --------------------------------------------------------------------------
  // TODO: add formal / simulation assertions:
  //   - hit_i and miss_i are mutually exclusive with access_i=0
  //   - dirty_evict_i implies eviction_i
  //   - cache_hits + cache_misses <= total_accesses (invariant)

`ifndef SYNTHESIS
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (hit_i && miss_i) begin
      $error("rvp_cache_stats: hit_i and miss_i both asserted");
    end
    if (dirty_evict_i && !eviction_i) begin
      $error("rvp_cache_stats: dirty_evict_i without eviction_i");
    end
  end
  // synthesis translate_on
`endif

endmodule
