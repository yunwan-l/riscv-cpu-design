/**
 * rvp_icache.sv - Instruction Cache (Core Module)
 *
 * =================================================================================
 * Two-stage pipelined, set-associative instruction cache.
 * =================================================================================
 * Pipeline stages:
 *   IC0 - Lookup issue (drive tag/data RAM read addresses)
 *   IC1 - Tag compare & hit decision, output data muxing
 *
 * Fill buffers (NUM_FB): decouple the lookup path from the miss-refill path.
 *   When a lookup misses, a fill buffer is allocated to track the outstanding
 *   memory request. Up to NUM_FB misses can be in flight concurrently so
 *   subsequent lookups to other lines can proceed (limited by RAM port
 *   contention).
 *
 * Miss handling state machine:
 *   IDLE -> LOOKUP -> MISS -> REFILL -> IDLE
 *
 * Replacement policy: delegated to rvp_cache_replacement. The cache controller
 * exposes the lookup result and pulses an update on fill / hit; the policy
 * module returns the victim way. POLICY is selectable at compile time so
 * different configurations can be benchmarked against the same controller.
 *
 * Statistics: every access/hit/miss/eviction is reported to rvp_cache_stats
 * for hit-rate analysis.
 *
 * Reference: ibex_icache.sv (1337 lines) - two-stage pipeline, fill buffers,
 *            output data muxing, round-robin way selection.
 */

module rvp_icache
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  // Error-correction code enable (placeholder for future ECC extension)
  parameter bit          ICacheECC    = 1'b0,
  // Number of fill buffers (must be >= 2)
  parameter int unsigned NUM_FB       = 4,
  // Bus latency in cycles (for modeling / stats; the cache itself uses the
  // handshake signals, this is only for AMAT estimation)
  parameter int unsigned BUS_LATENCY = 2
) (
  // --------------------------------------------------------------------------
  // Clock & reset
  // --------------------------------------------------------------------------
  input  logic          clk_i,
  input  logic          rst_ni,

  // --------------------------------------------------------------------------
  // Core-side interface (instruction fetch from IF stage)
  // --------------------------------------------------------------------------
  // Core is ready to accept an instruction this cycle
  input  logic          ready_i,
  // Cache presents a valid instruction this cycle
  output logic          valid_o,
  // Fetched instruction word
  output logic [31:0]   rdata_o,
  // Address of the fetched instruction (for branch / exception tracking)
  output logic [31:0]   addr_o,
  // Error on fetched instruction (bus error / ECC error)
  output logic          err_o,

  // --------------------------------------------------------------------------
  // Branch / request interface
  // --------------------------------------------------------------------------
  // Core requests an instruction (always high during normal execution)
  input  logic          req_i,
  // Branch target change - addr_i is the new fetch address
  input  logic          branch_i,
  input  logic [31:0]   addr_i,

  // --------------------------------------------------------------------------
  // Bus interface (to next-level memory / interconnect)
  // --------------------------------------------------------------------------
  output logic          req_o,
  input  logic          gnt_i,
  output logic [31:0]   bus_addr_o,
  input  logic [31:0]   bus_rdata_i,
  input  logic          bus_err_i,
  input  logic          bus_rvalid_i,

  // --------------------------------------------------------------------------
  // Tag RAM external interface (mirrors ibex_icache ic_tag_* ports)
  // --------------------------------------------------------------------------
  output logic [IC_NUM_WAYS-1:0]   ic_tag_req_o,
  output logic                     ic_tag_write_o,
  output logic [IC_INDEX_W-1:0]    ic_tag_addr_o,
  output logic [IC_TAG_SIZE-1:0]   ic_tag_wdata_o,
  input  logic [IC_TAG_SIZE-1:0]   ic_tag_rdata_i [IC_NUM_WAYS],

  // --------------------------------------------------------------------------
  // Data RAM external interface (mirrors ibex_icache ic_data_* ports)
  // --------------------------------------------------------------------------
  output logic [IC_NUM_WAYS-1:0]   ic_data_req_o,
  output logic                     ic_data_write_o,
  output logic [IC_INDEX_W-1:0]    ic_data_addr_o,
  output logic [IC_LINE_SIZE-1:0]  ic_data_wdata_o,
  input  logic [IC_LINE_SIZE-1:0]  ic_data_rdata_i [IC_NUM_WAYS],

  // --------------------------------------------------------------------------
  // Cache control / status
  // --------------------------------------------------------------------------
  input  logic          enable_i,        // 1 = cache active, 0 = bypass to bus
  input  logic          inval_i,         // 1 = request invalidation
  output logic          busy_o,          // 1 = cache busy (miss / flush in progress)

  // --------------------------------------------------------------------------
  // Statistics interface (to rvp_cache_stats)
  // --------------------------------------------------------------------------
  output logic         stats_access_o,
  output logic         stats_hit_o,
  output logic         stats_miss_o,
  output logic         stats_evict_o,
  output logic         stats_read_o,
  output logic         stats_write_o
);

  // ==========================================================================
  // Local parameters
  // ==========================================================================

  // Number of beats in a cache line (BUS is 32-bit, line is 64-bit -> 2 beats)
  localparam int unsigned LINE_BEATS    = IC_LINE_SIZE / DATA_W;
  localparam int unsigned LINE_BEATS_W  = $clog2(LINE_BEATS);

  // Fill buffer fill level threshold for lookup throttling
  localparam int unsigned FB_THRESHOLD  = NUM_FB - 2;

  // ==========================================================================
  // Internal signals: Pipeline stage IC0 (lookup issue)
  // ==========================================================================

  logic                   lookup_req_ic0;       // Issue a lookup this cycle
  logic [ADDR_W-1:0]      lookup_addr_ic0;      // Address to look up
  logic [IC_INDEX_W-1:0]   lookup_index_ic0;     // Set index
  logic                   lookup_grant_ic0;     // Lookup was granted (no stall)

  // Tag/data RAM request signals (driven by IC0)
  logic [IC_NUM_WAYS-1:0] tag_req_ic0;
  logic                   tag_write_ic0;
  logic [IC_INDEX_W-1:0]  tag_addr_ic0;
  logic [IC_TAG_SIZE-1:0]  tag_wdata_ic0;

  logic [IC_NUM_WAYS-1:0] data_req_ic0;
  logic                   data_write_ic0;
  logic [IC_INDEX_W-1:0]  data_addr_ic0;
  logic [IC_LINE_SIZE-1:0] data_wdata_ic0;

  // ==========================================================================
  // Internal signals: Pipeline stage IC1 (tag compare / hit)
  // ==========================================================================

  logic                   lookup_valid_ic1;     // IC1 has a valid lookup
  logic [ADDR_W-1:0]      lookup_addr_ic1;      // Address being compared
  logic [IC_INDEX_W-1:0]   lookup_index_ic1;     // Index (for refill / write)

  // Tag comparison
  logic [IC_NUM_WAYS-1:0] tag_match_ic1;        // Per-way tag match (tag bits equal)
  logic [IC_NUM_WAYS-1:0] tag_valid_ic1;         // Per-way valid bit
  logic [IC_NUM_WAYS-1:0] tag_hit_ic1;          // Per-way hit (match AND valid)
  logic                   tag_any_hit_ic1;      // OR of all tag_hit_ic1
  logic [IC_NUM_WAYS-1:0] tag_invalid_ic1;       // Per-way invalid (for fill allocation)
  logic [IC_NUM_WAYS-1:0] lowest_invalid_way_ic1; // First invalid way (one-hot)

  // Selected victim way (from replacement module)
  logic [IC_NUM_WAYS-1:0] replace_way_ic1;
  logic [IC_NUM_WAYS-1:0] sel_way_ic1;           // Final allocation way

  // Hit data muxing
  logic [IC_LINE_SIZE-1:0] hit_data_ic1;
  logic [31:0]             hit_word_ic1;
  logic                   ecc_err_ic1;

  // ==========================================================================
  // Fill buffers
  // ==========================================================================
  // Each fill buffer tracks a single outstanding miss. NUM_FB buffers allow
  // overlapping misses to be serviced as the bus returns data.
  //
  // TODO: full multi-buffer arbitration logic. The skeleton below models a
  // single in-flight fill for clarity; the multi-buffer version mirrors
  // ibex_icache.sv lines 125-260 (NUM_FB=4).

  logic [NUM_FB-1:0]      fill_busy_q, fill_busy_d;
  logic [NUM_FB-1:0]      fill_done;
  logic [NUM_FB-1:0]      fill_alloc_sel;
  logic [NUM_FB-1:0]      fill_alloc;
  logic [$clog2(NUM_FB)-1:0] fb_fill_level;

  logic [ADDR_W-1:0]      fill_addr_q [NUM_FB];
  logic [IC_NUM_WAYS-1:0] fill_way_q  [NUM_FB];
  logic [IC_LINE_SIZE-1:0] fill_data_q [NUM_FB];

  // External bus request (from the selected fill buffer)
  logic                   fill_ext_req;
  logic [ADDR_W-1:0]      fill_ext_addr;
  logic                   fill_ext_grant;
  logic                   fill_rvd_valid;
  logic [31:0]            fill_rvd_data;
  logic                   fill_rvd_err;

  // RAM write request (from the selected fill buffer)
  logic                   fill_ram_req;
  logic [IC_INDEX_W-1:0]   fill_ram_index;
  logic [IC_NUM_WAYS-1:0] fill_ram_way;
  logic [IC_LINE_SIZE-1:0] fill_ram_data;

  // ==========================================================================
  // Miss handling state machine
  // ==========================================================================
  cache_state_e state_q, state_d;

  // ==========================================================================
  // Invalidation state machine (delegated to rvp_cache_flush)
  // ==========================================================================
  logic                   flush_req;
  logic                   flush_done;
  logic                   flush_busy;
  logic [IC_NUM_WAYS-1:0] flush_tag_req;
  logic                   flush_tag_write;
  logic [IC_INDEX_W-1:0]  flush_tag_addr;
  logic                   flush_invalidate;

  // ==========================================================================
  // Output data muxing
  // ==========================================================================
  logic [31:0]            output_data;
  logic                   output_err;
  logic                   output_valid;
  logic [31:0]            output_addr;

  // ==========================================================================
  // Statistics counters (wired to rvp_cache_stats instance)
  // ==========================================================================
  // TODO: instantiate rvp_cache_stats here, or wire to a top-level instance.

  // ==========================================================================
  // Pipeline stage IC0: lookup issue
  // ==========================================================================
  // A lookup is requested when the core asks for an instruction and the cache
  // is enabled. Lookups are throttled when the fill buffer level exceeds the
  // threshold (to avoid overflowing the buffers with misses).
  //
  // Reference: ibex_icache.sv line 247-249.

  logic lookup_throttle;
  assign lookup_throttle = (fb_fill_level > FB_THRESHOLD[$clog2(NUM_FB)-1:0]);

  assign lookup_req_ic0 = req_i & enable_i & ~flush_busy & ~inval_i &
                          (branch_i | ~lookup_throttle);
  assign lookup_addr_ic0 = branch_i ? addr_i : output_addr;
  assign lookup_index_ic0 = lookup_addr_ic0[IC_INDEX_HI -: IC_INDEX_W];

  // TODO: grant logic - a lookup is granted unless the RAM port is taken by
  //       a fill writeback or an invalidation.
  assign lookup_grant_ic0 = lookup_req_ic0;  // simplified

  // Drive tag/data RAM reads in IC0. During a fill, the RAM is driven by the
  // fill buffer writeback path instead.
  // TODO: arbitrate between lookup reads and fill writes on the RAM port.
  assign tag_req_ic0   = {IC_NUM_WAYS{lookup_grant_ic0}};
  assign tag_write_ic0 = 1'b0;
  assign tag_addr_ic0  = lookup_index_ic0;
  assign tag_wdata_ic0 = '0;

  assign data_req_ic0   = {IC_NUM_WAYS{lookup_grant_ic0}};
  assign data_write_ic0 = 1'b0;
  assign data_addr_ic0  = lookup_index_ic0;
  assign data_wdata_ic0 = '0;

  // ==========================================================================
  // Pipeline stage IC1: tag compare & hit decision
  // ==========================================================================
  // The tag RAM outputs (combinational) are presented in IC1 one cycle after
  // the IC0 read request.

  // Register IC0 -> IC1
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      lookup_valid_ic1 <= 1'b0;
      lookup_addr_ic1  <= '0;
    end else if (lookup_grant_ic0) begin
      lookup_valid_ic1 <= 1'b1;
      lookup_addr_ic1  <= lookup_addr_ic0;
    end else begin
      lookup_valid_ic1 <= 1'b0;
    end
  end
  assign lookup_index_ic1 = lookup_addr_ic1[IC_INDEX_HI -: IC_INDEX_W];

  // Per-way tag comparison
  for (genvar w = 0; w < IC_NUM_WAYS; w++) begin : gen_tag_cmp
    // Unpack tag: [valid] [tag bits]
    logic tag_valid_bit;
    logic [ADDR_W-IC_INDEX_W-IC_LINE_W-1:0] tag_bits;
    assign tag_valid_bit = ic_tag_rdata_i[w][IC_TAG_SIZE-1];
    assign tag_bits      = ic_tag_rdata_i[w][IC_TAG_SIZE-2:0];

    assign tag_valid_ic1[w]   = tag_valid_bit;
    assign tag_invalid_ic1[w] = ~tag_valid_bit;
    assign tag_match_ic1[w]   = (tag_bits == lookup_addr_ic1[ADDR_W-1:IC_INDEX_HI+1]);
    assign tag_hit_ic1[w]     = tag_valid_bit & tag_match_ic1[w];
  end

  assign tag_any_hit_ic1 = |tag_hit_ic1;

  // First-invalid-way selection (one-hot)
  assign lowest_invalid_way_ic1[0] = tag_invalid_ic1[0];
  for (genvar w = 1; w < IC_NUM_WAYS; w++) begin : gen_lowest_inv
    assign lowest_invalid_way_ic1[w] = tag_invalid_ic1[w] &
                                       ~|tag_invalid_ic1[w-1:0];
  end

  // Allocation way: prefer first invalid, else replacement policy victim.
  assign sel_way_ic1 = |tag_invalid_ic1 ? lowest_invalid_way_ic1 :
                                        replace_way_ic1;

  // Hit data muxing - select the line data of the hitting way
  always_comb begin
    hit_data_ic1 = '0;
    for (int w = 0; w < IC_NUM_WAYS; w++) begin
      if (tag_hit_ic1[w]) hit_data_ic1 |= ic_data_rdata_i[w];
    end
  end

  // Word selection from the hit line based on line offset
  // TODO: support 32-bit instructions crossing a line boundary (RVC).
  assign hit_word_ic1 = hit_data_ic1[31:0];  // simplified: word 0 of line

  // ECC error detection (placeholder when ICacheECC=0)
  assign ecc_err_ic1 = 1'b0;

  // ==========================================================================
  // Replacement policy module instantiation
  // ==========================================================================
  // The policy module is policy-agnostic via its POLICY parameter; the same
  // controller works for all policies, which is what enables the comparative
  // hit-rate study that is the focus of this project.

  rvp_cache_replacement #(
    .NUM_WAYS (IC_NUM_WAYS),
    .POLICY   (IC_REPLACE_POLICY)
  ) u_replacement (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .lookup_valid_i  (lookup_valid_ic1),
    .lookup_hit_i    (tag_any_hit_ic1),
    .lookup_way_i    (tag_hit_ic1),
    .replace_way_o   (replace_way_ic1),
    .update_i        (lookup_valid_ic1),  // update on every lookup result
    .update_way_i    (tag_hit_ic1 | sel_way_ic1),
    .set_index_i     ({{(32-IC_INDEX_W){1'b0}}, lookup_index_ic1})
  );

  // ==========================================================================
  // Miss handling state machine
  // ==========================================================================
  // IDLE    -> LOOKUP : lookup issued in IC0, awaiting IC1 result
  // LOOKUP  -> MISS    : IC1 reports a miss, allocate fill buffer & request bus
  // MISS    -> REFILL : bus granted, transferring line data
  // REFILL  -> IDLE   : line written to RAM, lookup can resume
  //
  // TODO: integrate the fill buffer multi-request logic. The current skeleton
  //       uses a single outstanding request; the FSM transitions reflect a
  //       single miss at a time. Multi-buffer support is layered on top.

  always_comb begin
    state_d = state_q;
    // Default: stay
    unique case (state_q)
      CACHE_IDLE: begin
        if (lookup_valid_ic1 && !tag_any_hit_ic1) begin
          state_d = CACHE_MISS;
        end
      end
      CACHE_LOOKUP: begin
        // IC1 result is being computed
        state_d = CACHE_IDLE;
      end
      CACHE_MISS: begin
        if (fill_ext_grant) state_d = CACHE_REFILL;
      end
      CACHE_REFILL: begin
        if (fill_done[0]) state_d = CACHE_IDLE;  // TODO: per-buffer done
      end
      default: state_d = CACHE_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= CACHE_IDLE;
    else         state_q <= state_d;
  end

  // ==========================================================================
  // Fill buffer management
  // ==========================================================================
  // TODO: full NUM_FB buffer management. For the skeleton, we model a single
  //       buffer (index 0). The multi-buffer logic involves:
  //   1. Allocation: pick a free buffer (fill_busy_q==0) on a miss.
  //   2. Ordering: track fill_older_q[i][j] to maintain age ordering for
  //      fair RAM writeback arbitration.
  //   3. External request arbiter: round-robin across busy buffers.
  //   4. RAM write arbiter: serialize line writes to the single RAM port.
  //   5. Output arbiter: feed completed data to the IF stage.
  //
  // Reference: ibex_icache.sv lines 700-1000.

  // Single-buffer model (placeholder)
  assign fill_busy_d    = fill_busy_q;
  assign fill_alloc_sel = '0;
  assign fill_alloc     = '0;

  // External bus request (placeholder - issue when MISS state)
  assign fill_ext_req   = (state_q == CACHE_MISS);
  assign fill_ext_addr  = lookup_addr_ic1;
  assign fill_ext_grant = gnt_i;

  // Bus interface outputs
  assign req_o        = fill_ext_req;
  assign bus_addr_o   = fill_ext_addr;

  // Receive bus data
  assign fill_rvd_valid = bus_rvalid_i;
  assign fill_rvd_data  = bus_rdata_i;
  assign fill_rvd_err   = bus_err_i;

  // TODO: assemble multi-beat line data in fill_data_q[0]

  // ==========================================================================
  // Tag/Data RAM output muxing
  // ==========================================================================
  // During normal lookup: IC0 drives reads.
  // During refill: fill buffer drives writes.
  // During flush: flush module drives invalidating writes.
  //
  // TODO: proper 3-way arbitration. Currently prioritizes writes.

  always_comb begin
    // Defaults: lookup-driven
    ic_tag_req_o    = tag_req_ic0;
    ic_tag_write_o  = tag_write_ic0;
    ic_tag_addr_o   = tag_addr_ic0;
    ic_tag_wdata_o  = tag_wdata_ic0;
    ic_data_req_o   = data_req_ic0;
    ic_data_write_o = data_write_ic0;
    ic_data_addr_o  = data_addr_ic0;
    ic_data_wdata_o = data_wdata_ic0;

    // Refill writes override
    // TODO: gate by state_q == CACHE_REFILL and fill_ram_req
    if (state_q == CACHE_REFILL) begin
      // TODO: write tag and data for the filled line
      // ic_tag_req_o    = sel_way_ic1;
      // ic_tag_write_o  = 1'b1;
      // ic_tag_addr_o   = fill_ram_index;
      // ic_tag_wdata_o  = {1'b1, lookup_addr_ic1[ADDR_W-1:IC_INDEX_HI+1]};
      // ic_data_req_o   = sel_way_ic1;
      // ic_data_write_o = 1'b1;
      // ic_data_addr_o  = fill_ram_index;
      // ic_data_wdata_o = fill_ram_data;
    end

    // Flush overrides everything
    if (flush_busy) begin
      ic_tag_req_o    = flush_tag_req;
      ic_tag_write_o  = flush_tag_write;
      ic_tag_addr_o   = flush_tag_addr;
      ic_tag_wdata_o  = '0;
    end
  end

  // ==========================================================================
  // Output data muxing (to IF stage)
  // ==========================================================================
  // On a hit in IC1, present the hit word.
  // On a miss, present the fill buffer data once the requested beat arrives.
  // TODO: handle the case where the requested instruction is in an in-flight
  //       fill buffer (forwarding) without waiting for the RAM write.

  always_comb begin
    output_data  = hit_word_ic1;
    output_err   = ecc_err_ic1 | fill_rvd_err;
    output_valid = lookup_valid_ic1 & tag_any_hit_ic1 & ready_i;
    output_addr  = lookup_addr_ic1;
  end

  assign valid_o  = output_valid;
  assign rdata_o  = output_data;
  assign addr_o   = output_addr;
  assign err_o    = output_err;
  assign busy_o   = (state_q != CACHE_IDLE) | flush_busy;

  // ==========================================================================
  // Invalidation / flush submodule
  // ==========================================================================
  assign flush_req = inval_i | !enable_i;

  rvp_cache_flush #(
    .NUM_LINES (IC_NUM_LINES),
    .NUM_WAYS  (IC_NUM_WAYS)
  ) u_flush (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .flush_req_i   (flush_req),
    .flush_done_o  (flush_done),
    .tag_req_o     (flush_tag_req),
    .tag_write_o   (flush_tag_write),
    .tag_addr_o    (flush_tag_addr),
    .invalidate_o  (flush_invalidate),
    .busy_o        (flush_busy)
  );

  // ==========================================================================
  // Statistics outputs
  // ==========================================================================
  // Pulse hit / miss on every IC1 lookup completion.
  assign stats_access_o = lookup_valid_ic1;
  assign stats_hit_o    = lookup_valid_ic1 & tag_any_hit_ic1;
  assign stats_miss_o   = lookup_valid_ic1 & !tag_any_hit_ic1;
  assign stats_evict_o  = (state_q == CACHE_REFILL) & fill_done[0] &
                          (|tag_valid_ic1);  // evicted a valid line
  assign stats_read_o   = lookup_valid_ic1;  // I-Cache is read-only
  assign stats_write_o  = 1'b0;               // I-Cache is never written by SW

  // TODO: instantiate rvp_cache_stats here, or wire these pulses to a shared
  //       instance at the cache subsystem top level.

  // ==========================================================================
  // TODO list (consolidated)
  // ==========================================================================
  // 1. Multi-fill-buffer management (NUM_FB>1) with age tracking and
  //    fair arbitration - the biggest remaining piece.
  // 2. Output data forwarding from in-flight fill buffers (avoid waiting
  //    for the RAM writeback when the requested beat has arrived).
  // 3. Skid buffer for compressed (RVC) instructions that cross a line.
  // 4. ECC encode/decode when ICacheECC=1.
  // 5. Per-set replacement policy state (currently global in the policy
  //    module - needs set-indexed storage for accurate LRU/FIFO/RRIP).
  // 6. Prefetch: ibex increments a prefetch address on each granted lookup;
  //    add the same here to enable sequential-line prefetch.
  // 7. Formal properties / SV assertions for cache coherence invariants.

endmodule
