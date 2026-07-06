/**
 * rvp_dcache.sv - Data Cache (Core Module, Write-Back Capable)
 *
 * =================================================================================
 * Set-associative data cache with configurable write policy.
 * =================================================================================
 * Build progression:
 *   Phase 3a (initial): write-through, no dirty bit management
 *   Phase 3b (optimized): write-back with dirty bit, writeback on eviction
 *
 * Compared to rvp_icache.sv the D-Cache adds:
 *   - Dirty bit in the tag (dcache_tag_t)
 *   - Write-hit handling (write into the cached line)
 *   - Write-back state in the FSM (CACHE_WB) to evict dirty lines
 *   - Byte-enable writes (data_be_i) for sub-word stores
 *   - Write statistics in addition to read statistics
 *
 * The replacement policy interface and the statistics interface are identical
 * to the I-Cache, so the same rvp_cache_replacement / rvp_cache_stats modules
 * are reused - enabling apples-to-apples hit-rate comparison between caches
 * and policies.
 *
 * Reference: ibex does not ship a D-Cache. The structure here follows the
 *            I-Cache layout (two-stage pipeline, fill buffers, miss FSM) with
 *            the additions noted above. Common academic references:
 *            - Hennessy & Patterson, "Computer Architecture: A Quantitative
 *              Approach", Chapter 2 (cache hierarchy, write policies).
 *            - Sawyer et al., "Write-back vs write-through" analysis.
 */

module rvp_dcache
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  // Error-correction code enable (placeholder)
  parameter bit          DCacheECC    = 1'b0,
  // Number of fill buffers (must be >= 2)
  parameter int unsigned NUM_FB       = 4,
  // Write policy: 0 = write-through, 1 = write-back
  // Write-through is the Phase 3a default; write-back is the optimization.
  parameter bit          WRITE_BACK   = 1'b1,
  // Bus latency in cycles (modeling only)
  parameter int unsigned BUS_LATENCY = 2
) (
  // --------------------------------------------------------------------------
  // Clock & reset
  // --------------------------------------------------------------------------
  input  logic          clk_i,
  input  logic          rst_ni,

  // --------------------------------------------------------------------------
  // Core-side interface (load/store unit)
  // --------------------------------------------------------------------------
  // Core requests a data access this cycle
  input  logic          req_i,
  // Core is ready to accept the response
  input  logic          ready_i,
  // Cache presents a valid response
  output logic          valid_o,
  // Read data output (for loads)
  output logic [31:0]   rdata_o,
  // Address of the access (for tracking)
  output logic [31:0]   addr_o,
  // Error on access
  output logic          err_o,

  // --------------------------------------------------------------------------
  // Access type / control
  // --------------------------------------------------------------------------
  // 1 = read (load), 0 = write (store)
  input  logic          read_i,
  // 1 = write (store)
  input  logic          write_i,
  // Byte-enable for sub-word stores (one bit per byte)
  input  logic [3:0]    data_be_i,
  // Write data for stores
  input  logic [31:0]   data_wdata_i,
  // Access size (B/H/W) - for address alignment and byte-enable generation
  input  mem_size_e     data_size_i,

  // --------------------------------------------------------------------------
  // Bus interface (to next-level memory / interconnect)
  // --------------------------------------------------------------------------
  output logic          req_o,
  input  logic          gnt_i,
  output logic [31:0]   bus_addr_o,
  output logic          bus_we_o,        // 1 = write (writeback), 0 = read (fill)
  output logic [3:0]    bus_be_o,
  output logic [31:0]   bus_wdata_o,
  input  logic [31:0]   bus_rdata_i,
  input  logic          bus_err_i,
  input  logic          bus_rvalid_i,

  // --------------------------------------------------------------------------
  // Tag RAM external interface
  // --------------------------------------------------------------------------
  // Tag storage is the dcache_tag_t packed struct: [valid][dirty][tag]
  output logic [DC_NUM_WAYS-1:0]   dc_tag_req_o,
  output logic                     dc_tag_write_o,
  output logic [DC_INDEX_W-1:0]    dc_tag_addr_o,
  output logic [DC_TAG_SIZE-1:0]   dc_tag_wdata_o,
  input  logic [DC_TAG_SIZE-1:0]   dc_tag_rdata_i [DC_NUM_WAYS],

  // --------------------------------------------------------------------------
  // Data RAM external interface
  // --------------------------------------------------------------------------
  output logic [DC_NUM_WAYS-1:0]   dc_data_req_o,
  output logic                     dc_data_write_o,
  output logic [DC_INDEX_W-1:0]    dc_data_addr_o,
  output logic [DC_LINE_SIZE-1:0]  dc_data_wdata_o,
  output logic [DC_LINE_SIZE/8-1:0] dc_data_be_o,  // byte-enable for partial writes
  input  logic [DC_LINE_SIZE-1:0]  dc_data_rdata_i [DC_NUM_WAYS],

  // --------------------------------------------------------------------------
  // Cache control / status
  // --------------------------------------------------------------------------
  input  logic          enable_i,        // 1 = cache active, 0 = bypass to bus
  input  logic          flush_req_i,     // 1 = request flush (writeback + inval)
  input  logic          inval_i,         // 1 = request invalidation (no writeback)
  output logic          flush_done_o,    // 1 = flush / inval complete
  output logic          busy_o,          // 1 = cache busy

  // --------------------------------------------------------------------------
  // Statistics interface (to rvp_cache_stats)
  // --------------------------------------------------------------------------
  output logic         stats_access_o,
  output logic         stats_hit_o,
  output logic         stats_miss_o,
  output logic         stats_evict_o,
  output logic         stats_dirty_evict_o,
  output logic         stats_read_o,
  output logic         stats_write_o
);

  // ==========================================================================
  // Local parameters
  // ==========================================================================

  localparam int unsigned LINE_BEATS    = DC_LINE_SIZE / DATA_W;
  localparam int unsigned LINE_BEATS_W = $clog2(LINE_BEATS);
  localparam int unsigned FB_THRESHOLD = NUM_FB - 2;

  // ==========================================================================
  // Pipeline stage DC0 (lookup issue)
  // ==========================================================================

  logic                   lookup_req_dc0;
  logic [ADDR_W-1:0]      lookup_addr_dc0;
  logic [DC_INDEX_W-1:0]   lookup_index_dc0;
  logic                   lookup_grant_dc0;

  logic [DC_NUM_WAYS-1:0] tag_req_dc0;
  logic                   tag_write_dc0;
  logic [DC_INDEX_W-1:0]  tag_addr_dc0;
  logic [DC_TAG_SIZE-1:0]  tag_wdata_dc0;

  logic [DC_NUM_WAYS-1:0] data_req_dc0;
  logic                   data_write_dc0;
  logic [DC_INDEX_W-1:0]  data_addr_dc0;
  logic [DC_LINE_SIZE-1:0] data_wdata_dc0;
  logic [DC_LINE_SIZE/8-1:0] data_be_dc0;

  // ==========================================================================
  // Pipeline stage DC1 (tag compare & hit decision)
  // ==========================================================================

  logic                   lookup_valid_dc1;
  logic [ADDR_W-1:0]      lookup_addr_dc1;
  logic [DC_INDEX_W-1:0]   lookup_index_dc1;

  logic [DC_NUM_WAYS-1:0] tag_match_dc1;
  logic [DC_NUM_WAYS-1:0] tag_valid_dc1;
  logic [DC_NUM_WAYS-1:0] tag_dirty_dc1;
  logic [DC_NUM_WAYS-1:0] tag_hit_dc1;
  logic                   tag_any_hit_dc1;
  logic [DC_NUM_WAYS-1:0] tag_invalid_dc1;
  logic [DC_NUM_WAYS-1:0] lowest_invalid_way_dc1;

  logic [DC_NUM_WAYS-1:0] replace_way_dc1;
  logic [DC_NUM_WAYS-1:0] sel_way_dc1;

  logic [DC_LINE_SIZE-1:0] hit_data_dc1;
  logic [31:0]            hit_word_dc1;
  logic                   ecc_err_dc1;

  // Write-hit handling
  logic                   write_hit_dc1;
  logic [DC_NUM_WAYS-1:0] write_hit_way_dc1;
  logic [DC_LINE_SIZE-1:0] write_merged_data;
  logic [DC_LINE_SIZE/8-1:0] write_merged_be;

  // ==========================================================================
  // Fill buffers
  // ==========================================================================
  logic [NUM_FB-1:0]      fill_busy_q, fill_busy_d;
  logic [NUM_FB-1:0]      fill_done;

  logic [ADDR_W-1:0]      fill_addr_q [NUM_FB];
  logic [DC_NUM_WAYS-1:0] fill_way_q  [NUM_FB];
  logic [DC_LINE_SIZE-1:0] fill_data_q [NUM_FB];

  // Writeback buffer (single, for dirty evict path)
  logic                   wb_valid_q, wb_valid_d;
  logic [ADDR_W-1:0]      wb_addr_q;
  logic [DC_LINE_SIZE-1:0] wb_data_q;
  logic [DC_NUM_WAYS-1:0] wb_way_q;

  logic                   fill_ext_req;
  logic [ADDR_W-1:0]      fill_ext_addr;
  logic                   fill_ext_we;
  logic [31:0]            fill_ext_wdata;
  logic                   fill_ext_grant;
  logic                   fill_rvd_valid;
  logic [31:0]            fill_rvd_data;
  logic                   fill_rvd_err;

  logic                   fill_ram_req;
  logic [DC_INDEX_W-1:0]   fill_ram_index;
  logic [DC_NUM_WAYS-1:0] fill_ram_way;
  logic [DC_LINE_SIZE-1:0] fill_ram_data;

  // ==========================================================================
  // Miss / writeback FSM
  // ==========================================================================
  cache_state_e state_q, state_d;

  // ==========================================================================
  // Flush submodule
  // ==========================================================================
  logic                   flush_req_internal;
  logic                   flush_done_internal;
  logic                   flush_busy;
  logic [DC_NUM_WAYS-1:0] flush_tag_req;
  logic                   flush_tag_write;
  logic [DC_INDEX_W-1:0]  flush_tag_addr;
  logic                   flush_invalidate;

  // ==========================================================================
  // Output muxing
  // ==========================================================================
  logic [31:0]            output_data;
  logic                   output_err;
  logic                   output_valid;
  logic [31:0]            output_addr;

  // ==========================================================================
  // Pipeline stage DC0: lookup issue
  // ==========================================================================
  // D-Cache lookup is gated by the FSM state (no lookup during refill / WB /
  // flush). Both reads and writes start as lookups; the write path is
  // differentiated in DC1.

  logic lookup_throttle;
  assign lookup_throttle = 1'b0;  // TODO: gate by fill buffer level

  assign lookup_req_dc0  = req_i & enable_i & ~flush_busy &
                            (state_q == CACHE_IDLE) & ~lookup_throttle;
  assign lookup_addr_dc0 = addr_i;  // assume LSU drives addr_i directly
  assign lookup_index_dc0 = lookup_addr_dc0[DC_INDEX_HI -: DC_INDEX_W];
  assign lookup_grant_dc0 = lookup_req_dc0;

  assign tag_req_dc0   = {DC_NUM_WAYS{lookup_grant_dc0}};
  assign tag_write_dc0 = 1'b0;
  assign tag_addr_dc0  = lookup_index_dc0;
  assign tag_wdata_dc0 = '0;

  assign data_req_dc0   = {DC_NUM_WAYS{lookup_grant_dc0}};
  assign data_write_dc0 = 1'b0;
  assign data_addr_dc0  = lookup_index_dc0;
  assign data_wdata_dc0 = '0;
  assign data_be_dc0    = '0;

  // ==========================================================================
  // Pipeline stage DC1: tag compare & hit decision
  // ==========================================================================

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lookup_valid_dc1 <= 1'b0;
      lookup_addr_dc1  <= '0;
    end else if (lookup_grant_dc0) begin
      lookup_valid_dc1 <= 1'b1;
      lookup_addr_dc1  <= lookup_addr_dc0;
    end else begin
      lookup_valid_dc1 <= 1'b0;
    end
  end
  assign lookup_index_dc1 = lookup_addr_dc1[DC_INDEX_HI -: DC_INDEX_W];

  // Per-way tag comparison (dcache_tag_t: [valid][dirty][tag])
  for (genvar w = 0; w < DC_NUM_WAYS; w++) begin : gen_tag_cmp
    logic tag_valid_bit;
    logic tag_dirty_bit;
    logic [ADDR_W-DC_INDEX_W-DC_LINE_W-1:0] tag_bits;

    assign tag_valid_bit = dc_tag_rdata_i[w][DC_TAG_SIZE-1];
    assign tag_dirty_bit = dc_tag_rdata_i[w][DC_TAG_SIZE-2];
    assign tag_bits      = dc_tag_rdata_i[w][DC_TAG_SIZE-3:0];

    assign tag_valid_dc1[w]   = tag_valid_bit;
    assign tag_dirty_dc1[w]   = tag_dirty_bit;
    assign tag_invalid_dc1[w] = ~tag_valid_bit;
    assign tag_match_dc1[w]   = (tag_bits == lookup_addr_dc1[ADDR_W-1:DC_INDEX_HI+1]);
    assign tag_hit_dc1[w]     = tag_valid_bit & tag_match_dc1[w];
  end

  assign tag_any_hit_dc1 = |tag_hit_dc1;
  assign write_hit_dc1   = lookup_valid_dc1 & tag_any_hit_dc1 & write_i;
  // Write hits the first matching way (only one way can match)
  assign write_hit_way_dc1 = tag_hit_dc1;

  // First-invalid-way selection
  assign lowest_invalid_way_dc1[0] = tag_invalid_dc1[0];
  for (genvar w = 1; w < DC_NUM_WAYS; w++) begin : gen_lowest_inv
    assign lowest_invalid_way_dc1[w] = tag_invalid_dc1[w] &
                                       ~|tag_invalid_dc1[w-1:0];
  end

  // Allocation way: prefer first invalid, else replacement victim.
  assign sel_way_dc1 = |tag_invalid_dc1 ? lowest_invalid_way_dc1 :
                                          replace_way_dc1;

  // Hit data muxing
  always_comb begin
    hit_data_dc1 = '0;
    for (int w = 0; w < DC_NUM_WAYS; w++) begin
      if (tag_hit_dc1[w]) hit_data_dc1 |= dc_data_rdata_i[w];
    end
  end

  // Word selection from the hit line based on line offset
  // TODO: handle sub-word alignment and sign extension
  assign hit_word_dc1 = hit_data_dc1[31:0];

  assign ecc_err_dc1 = 1'b0;

  // ==========================================================================
  // Write-hit handling (write-through / write-back)
  // ==========================================================================
  // On a write hit:
  //   write-through: update the cache AND forward the store to the bus
  //   write-back:    update only the cache, set the dirty bit
  //
  // The merged line data is computed by overlaying the store bytes onto the
  // existing line. The byte-enable mask selects which bytes to overwrite.
  //
  // TODO: generate the byte-enable mask from data_be_i and the line offset.

  always_comb begin
    // Default: pass through the existing line
    write_merged_data = hit_data_dc1;
    write_merged_be   = '0;
    // TODO: overlay data_wdata_i at the correct word offset within the line
    //       and set the corresponding byte-enable bits.
    //   for (int b = 0; b < 4; b++) begin
    //     if (data_be_i[b]) begin
    //       write_merged_data[word_offset*32 + b*8 +: 8] = data_wdata_i[b*8 +: 8];
    //       write_merged_be[word_offset*4 + b] = 1'b1;
    //     end
    //   end
  end

  // ==========================================================================
  // Replacement policy module
  // ==========================================================================
  rvp_cache_replacement #(
    .NUM_WAYS (DC_NUM_WAYS),
    .POLICY   (DC_REPLACE_POLICY)
  ) u_replacement (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .lookup_valid_i  (lookup_valid_dc1),
    .lookup_hit_i    (tag_any_hit_dc1),
    .lookup_way_i    (tag_hit_dc1),
    .replace_way_o   (replace_way_dc1),
    .update_i        (lookup_valid_dc1),
    .update_way_i    (tag_hit_dc1 | sel_way_dc1),
    .set_index_i     (lookup_index_dc1)
  );

  // ==========================================================================
  // Miss / writeback FSM
  // ==========================================================================
  // IDLE    -> LOOKUP : lookup issued
  // LOOKUP  -> MISS    : DC1 reports a miss (read or write)
  // MISS    -> REFILL  : bus granted, transferring line data
  // REFILL  -> IDLE    : line written to RAM
  //
  // Write-back path (when WRITE_BACK=1 and the victim way is dirty):
  //   MISS    -> CACHE_WB : victim is dirty, issue writeback
  //   CACHE_WB -> REFILL   : writeback complete, now refill
  //
  // The CACHE_WB state is what distinguishes write-back from write-through:
  // in write-through mode the dirty bit is never set, so this transition is
  // never taken.

  logic victim_dirty;
  assign victim_dirty = |(tag_dirty_dc1 & sel_way_dc1);

  always_comb begin
    state_d = state_q;
    unique case (state_q)
      CACHE_IDLE: begin
        if (lookup_valid_dc1 && !tag_any_hit_dc1) begin
          // Miss: need to refill (and possibly write back first)
          if (WRITE_BACK && victim_dirty) state_d = CACHE_WB;
          else                            state_d = CACHE_MISS;
        end
      end
      CACHE_LOOKUP: state_d = CACHE_IDLE;
      CACHE_MISS: begin
        if (fill_ext_grant) state_d = CACHE_REFILL;
      end
      CACHE_WB: begin
        // Wait for writeback to complete, then proceed to refill
        // TODO: track writeback completion via a sub-FSM or counter
        if (fill_ext_grant && fill_rvd_valid) state_d = CACHE_MISS;
      end
      CACHE_REFILL: begin
        if (fill_done[0]) state_d = CACHE_IDLE;
      end
      default: state_d = CACHE_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= CACHE_IDLE;
    else         state_q <= state_d;
  end

  // ==========================================================================
  // Writeback buffer management
  // ==========================================================================
  // When a dirty victim is selected, the dirty line is copied into the
  // writeback buffer and the bus is asked to write it back before the new
  // line is filled.
  //
  // TODO: full writeback buffer handshake with the bus interface.

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_valid_q <= 1'b0;
      wb_addr_q  <= '0;
      wb_data_q  <= '0;
      wb_way_q   <= '0;
    end else if (state_q == CACHE_IDLE && lookup_valid_dc1 &&
                 !tag_any_hit_dc1 && WRITE_BACK && victim_dirty) begin
      // Latch the dirty line for writeback
      wb_valid_q <= 1'b1;
      // Reconstruct the address from the victim's tag + current index
      // TODO: reconstruct wb_addr_q from the victim way's tag
      wb_addr_q  <= lookup_addr_dc1;
      wb_data_q  <= hit_data_dc1;  // TODO: select the victim way's data, not hit
      wb_way_q   <= sel_way_dc1;
    end else if (state_q == CACHE_WB && fill_ext_grant && fill_rvd_valid) begin
      wb_valid_q <= 1'b0;  // writeback complete
    end
  end

  // ==========================================================================
  // Bus interface
  // ==========================================================================
  // The bus is shared between:
  //   - Read requests (cache fill on miss)
  //   - Write requests (writeback of dirty victim, or write-through store)
  // TODO: arbitrate between fill and writeback paths.

  always_comb begin
    fill_ext_req   = 1'b0;
    fill_ext_addr  = '0;
    fill_ext_we    = 1'b0;
    fill_ext_wdata = '0;

    unique case (state_q)
      CACHE_MISS: begin
        // Read request for line fill
        fill_ext_req   = 1'b1;
        fill_ext_addr  = lookup_addr_dc1;
        fill_ext_we    = 1'b0;
      end
      CACHE_WB: begin
        // Write request for dirty line writeback
        fill_ext_req   = 1'b1;
        fill_ext_addr  = wb_addr_q;
        fill_ext_we    = 1'b1;
        fill_ext_wdata = wb_data_q[31:0];  // TODO: multi-beat
      end
      default: begin
        // Write-through: forward stores on a write miss
        if (WRITE_BACK == 1'b0 && lookup_valid_dc1 && write_i) begin
          fill_ext_req   = 1'b1;
          fill_ext_addr  = lookup_addr_dc1;
          fill_ext_we    = 1'b1;
          fill_ext_wdata = data_wdata_i;
        end
      end
    endcase
  end

  assign fill_ext_grant = gnt_i;

  assign req_o        = fill_ext_req;
  assign bus_addr_o   = fill_ext_addr;
  assign bus_we_o     = fill_ext_we;
  assign bus_wdata_o  = fill_ext_wdata;
  assign bus_be_o     = data_be_i;

  assign fill_rvd_valid = bus_rvalid_i;
  assign fill_rvd_data  = bus_rdata_i;
  assign fill_rvd_err   = bus_err_i;

  // ==========================================================================
  // Tag/Data RAM output muxing
  // ==========================================================================
  always_comb begin
    // Defaults: lookup-driven reads
    dc_tag_req_o    = tag_req_dc0;
    dc_tag_write_o  = tag_write_dc0;
    dc_tag_addr_o   = tag_addr_dc0;
    dc_tag_wdata_o  = tag_wdata_dc0;
    dc_data_req_o   = data_req_dc0;
    dc_data_write_o = data_write_dc0;
    dc_data_addr_o  = data_addr_dc0;
    dc_data_wdata_o = data_wdata_dc0;
    dc_data_be_o    = data_be_dc0;

    // Write-hit: update data RAM (and tag dirty bit if write-back)
    if (write_hit_dc1) begin
      dc_data_req_o    = write_hit_way_dc1;
      dc_data_write_o  = 1'b1;
      dc_data_addr_o   = lookup_index_dc1;
      dc_data_wdata_o  = write_merged_data;
      dc_data_be_o     = write_merged_be;
      // TODO: set dirty bit in tag RAM when WRITE_BACK=1
      //   dc_tag_req_o   = write_hit_way_dc1;
      //   dc_tag_write_o = 1'b1;
      //   dc_tag_addr_o  = lookup_index_dc1;
      //   dc_tag_wdata_o = {1'b1, 1'b1, lookup_addr_dc1[ADDR_W-1:DC_INDEX_HI+1]};
    end

    // Refill: write tag + data for the newly filled line
    if (state_q == CACHE_REFILL) begin
      dc_tag_req_o    = sel_way_dc1;
      dc_tag_write_o  = 1'b1;
      dc_tag_addr_o   = lookup_index_dc1;
      // Tag = valid=1, dirty=0 (clean on fill), tag bits
      dc_tag_wdata_o  = {1'b1, 1'b0, lookup_addr_dc1[ADDR_W-1:DC_INDEX_HI+1]};
      dc_data_req_o   = sel_way_dc1;
      dc_data_write_o = 1'b1;
      dc_data_addr_o  = lookup_index_dc1;
      dc_data_wdata_o = fill_ram_data;
      dc_data_be_o    = '1;  // write whole line
    end

    // Flush overrides everything
    if (flush_busy) begin
      dc_tag_req_o    = flush_tag_req;
      dc_tag_write_o  = flush_tag_write;
      dc_tag_addr_o   = flush_tag_addr;
      dc_tag_wdata_o  = '0;  // invalidate: valid=0
    end
  end

  // ==========================================================================
  // Output data muxing
  // ==========================================================================
  always_comb begin
    output_data  = hit_word_dc1;
    output_err   = ecc_err_dc1 | fill_rvd_err;
    output_valid = lookup_valid_dc1 & tag_any_hit_dc1 & ready_i & read_i;
    output_addr  = lookup_addr_dc1;
    // TODO: on a read miss, present fill_rvd_data once the requested beat
    //       arrives (forwarding from fill buffer).
  end

  assign valid_o  = output_valid;
  assign rdata_o  = output_data;
  assign addr_o   = output_addr;
  assign err_o    = output_err;
  assign busy_o   = (state_q != CACHE_IDLE) | flush_busy | wb_valid_q;

  // ==========================================================================
  // Flush submodule
  // ==========================================================================
  assign flush_req_internal = flush_req_i | inval_i | !enable_i;

  rvp_cache_flush #(
    .NUM_LINES (DC_NUM_LINES),
    .NUM_WAYS  (DC_NUM_WAYS)
  ) u_flush (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .flush_req_i   (flush_req_internal),
    .flush_done_o  (flush_done_internal),
    .tag_req_o     (flush_tag_req),
    .tag_write_o   (flush_tag_write),
    .tag_addr_o    (flush_tag_addr),
    .invalidate_o  (flush_invalidate),
    .busy_o        (flush_busy)
  );

  assign flush_done_o = flush_done_internal;

  // ==========================================================================
  // Statistics outputs
  // ==========================================================================
  assign stats_access_o       = lookup_valid_dc1;
  assign stats_hit_o          = lookup_valid_dc1 & tag_any_hit_dc1;
  assign stats_miss_o         = lookup_valid_dc1 & !tag_any_hit_dc1;
  assign stats_evict_o        = (state_q == CACHE_REFILL) & fill_done[0] &
                                (|tag_valid_dc1);
  assign stats_dirty_evict_o  = (state_q == CACHE_WB) & wb_valid_q;
  assign stats_read_o         = lookup_valid_dc1 & read_i;
  assign stats_write_o        = lookup_valid_dc1 & write_i;

  // ==========================================================================
  // TODO list (consolidated)
  // ==========================================================================
  // 1. Multi-beat line fill / writeback - currently modelled as single beat.
  //    The line is DC_LINE_SIZE bits = 8 bytes = 2 bus beats. Implement a
  //    beat counter in the fill / writeback FSM.
  // 2. Sub-word store alignment - generate write_merged_be and
  //    write_merged_data correctly from data_be_i and the line offset.
  // 3. Write-back tag update - set the dirty bit on write-hit when
  //    WRITE_BACK=1. Currently the tag write on write-hit is stubbed out.
  // 4. AMO / atomic operations (LR/SC) - not required for RV32I baseline
  //    but needed for full RV32A. Reserve hooks now.
  // 5. Coherence: when a bus master writes to a cached line externally
  //    (e.g. DMA), the D-Cache line must be invalidated. Add a snoop port.
  // 6. Per-set replacement policy state (same TODO as I-Cache).
  // 7. Writeback buffer should support multiple outstanding dirty evictions
  //    in conjunction with the multi-fill-buffer design.
  // 8. Critical-word-first: on a refill, return the requested word to the
  //    LSU as soon as it arrives, before the rest of the line is filled.
  //    This reduces visible miss latency.

endmodule
