/**
 * rvp_cache_flush.sv - Cache Flush / Invalidation Module
 *
 * Walks every set in the tag RAM and writes an invalid tag, clearing the
 * valid bit on all ways. Used for:
 *   - Power-on / reset initialization of the tag RAM (so unused lines are
 *     not mistaken for valid entries).
 *   - Software-initiated cache invalidation (e.g. before DMA, after
 *     self-modifying code, or as part of a fence.i).
 *   - D-Cache writeback-and-flush (TODO: extend to write back dirty lines
 *     before invalidating - see CACHE_WB integration in rvp_dcache.sv).
 *
 * State machine: IDLE -> FLUSHING (index sweep) -> DONE -> IDLE
 *
 * Reference: ibex_icache.sv inval_state_e (lines 193-198, 1207-1295).
 */

module rvp_cache_flush
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  // Number of lines per way (sets) to walk through
  parameter int unsigned NUM_LINES = 256,
  // Number of ways (we invalidate all ways per index simultaneously)
  parameter int unsigned NUM_WAYS  = 2
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  // --------------------------------------------------------------------------
  // Flush control interface
  // --------------------------------------------------------------------------
  input  logic                    flush_req_i,    // 1 = request a flush
  output logic                    flush_done_o,   // 1 = flush completed

  // --------------------------------------------------------------------------
  // Tag RAM control outputs (driven during FLUSHING)
  // --------------------------------------------------------------------------
  output logic [NUM_WAYS-1:0]     tag_req_o,      // request all ways
  output logic                    tag_write_o,    // 1 = write (invalidate)
  output logic [$clog2(NUM_LINES)-1:0] tag_addr_o, // current index
  output logic                    invalidate_o,   // force valid=0 on tag RAM
  output logic                    busy_o          // 1 = flush in progress
);

  // --------------------------------------------------------------------------
  // State machine
  // --------------------------------------------------------------------------
  // IDLE       - waiting for a flush request
  // FLUSHING   - sweeping all indices, writing invalid tags
  // DONE       - flush complete, signal flush_done_o for one cycle
  //
  // Note: ibex uses OUT_OF_RESET -> AWAIT_SCRAMBLE_KEY -> INVAL_CACHE -> IDLE
  //       because it integrates with a scrambling-key handshake. RVP does not
  //       scramble, so the simpler 3-state machine suffices.

  typedef enum logic [1:0] {
    FLUSH_IDLE     = 2'd0,
    FLUSH_RUNNING  = 2'd1,
    FLUSH_DONE     = 2'd2
  } flush_state_e;

  flush_state_e state_q, state_d;

  // Current index being invalidated
  logic [$clog2(NUM_LINES)-1:0] index_q, index_d;
  logic                          index_en;

  // --------------------------------------------------------------------------
  // Next-state / output logic
  // --------------------------------------------------------------------------
  always_comb begin
    // Defaults
    state_d        = state_q;
    index_d        = index_q;
    index_en       = 1'b0;
    tag_req_o      = '0;
    tag_write_o    = 1'b0;
    tag_addr_o     = index_q;
    invalidate_o   = 1'b0;
    busy_o         = 1'b1;
    flush_done_o   = 1'b0;

    unique case (state_q)
      FLUSH_IDLE: begin
        busy_o = 1'b0;
        if (flush_req_i) begin
          // Start the sweep from index 0
          state_d  = FLUSH_RUNNING;
          index_d  = '0;
          index_en = 1'b1;
        end
      end

      FLUSH_RUNNING: begin
        // Invalidate all ways of the current index.
        tag_req_o    = {NUM_WAYS{1'b1}};
        tag_write_o  = 1'b1;
        invalidate_o = 1'b1;
        tag_addr_o   = index_q;

        // Advance to the next index
        index_d  = index_q + 1'b1;
        index_en = 1'b1;

        // Stop when we've written the last index (wrap to 0)
        // Use &index_q to detect all-ones
        if (&index_q) begin
          state_d = FLUSH_DONE;
        end
      end

      FLUSH_DONE: begin
        // Pulse done for one cycle then return to idle
        flush_done_o = 1'b1;
        busy_o       = 1'b0;
        state_d      = FLUSH_IDLE;
      end

      default: state_d = FLUSH_IDLE;
    endcase
  end

  // --------------------------------------------------------------------------
  // State register
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= FLUSH_IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  // --------------------------------------------------------------------------
  // Index register
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      index_q <= '0;
    end else if (index_en) begin
      index_q <= index_d;
    end
  end

  // --------------------------------------------------------------------------
  // TODO: Writeback-before-flush for D-Cache
  // --------------------------------------------------------------------------
  // For the D-Cache, a "flush" should optionally write back dirty lines
  // before invalidating them. Suggested approach:
  //   1. Add a parameter WRITEBACK_ON_FLUSH (default 0 for I-Cache, 1 for D-Cache)
  //   2. Add a new state FLUSH_WB between FLUSH_RUNNING for each index:
  //      - read tag, check dirty bit
  //      - if dirty, issue a bus writeback request for that line
  //      - wait for writeback completion
  //      - then invalidate
  //   3. Coordinate with the cache controller so it does not issue lookups
  //      while a flush is in progress (busy_o gates the controller).
  //
  // This is left as TODO because it depends on the D-Cache bus interface
  // details that are still being finalized in rvp_dcache.sv.

  // --------------------------------------------------------------------------
  // TODO: Selective flush by address range
  // --------------------------------------------------------------------------
  // Software sometimes needs to flush only a range of addresses (e.g. after
  // DMA into a buffer). Add a range-based flush mode:
  //   - inputs flush_addr_lo_i, flush_addr_hi_i
  //   - compute set range from these and only walk that range
  // This is a future enhancement.

  // --------------------------------------------------------------------------
  // Assertions
  // --------------------------------------------------------------------------
  // TODO: add SV assertions:
  //   - flush_done_o is a one-cycle pulse
  //   - tag_req_o is all-ones only during FLUSH_RUNNING
  //   - busy_o is high for the entire flush duration

`ifndef SYNTHESIS
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (state_q == FLUSH_DONE && flush_done_o !== 1'b1) begin
      $error("rvp_cache_flush: flush_done_o not asserted in FLUSH_DONE");
    end
  end
  // synthesis translate_on
`endif

endmodule
