/**
 * rvp_cache_tag_array.sv - Cache Tag Storage Array
 *
 * Parameterized tag RAM for set-associative caches. Provides one independent
 * read/write port per way so the cache controller can read all ways in
 * parallel for tag comparison and write a single way on refill / invalidate.
 *
 * On reset all valid bits are cleared (no implicit tag initialization is
 * required from the controller - matches ibex behaviour where invalid tags
 * are implied by valid=0).
 *
 * Reference: ibex_icache.sv tag RAM external interface (ic_tag_req_o ... )
 *            The actual storage is instantiated outside ibex_icache; this
 *            module provides the equivalent storage for the RVP project.
 */

module rvp_cache_tag_array
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  // Number of ways (associativity)
  parameter int unsigned NUM_WAYS  = 2,
  // Number of lines per way (set count)
  parameter int unsigned NUM_LINES = 256,
  // Tag width INCLUDING the valid bit (and dirty bit for D-cache)
  parameter int unsigned TAG_SIZE  = 22
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,

  // Per-way write enable (one-hot). A request is issued when req_i[way]=1.
  input  logic [NUM_WAYS-1:0]             req_i,
  // 1 = write (refill/invalidate), 0 = read (lookup)
  input  logic                            write_i,
  // Index into the set (shared across all ways)
  input  logic [$clog2(NUM_LINES)-1:0]    addr_i,
  // Tag data to write (only meaningful when write_i=1)
  input  logic [TAG_SIZE-1:0]             wdata_i,
  // Per-way tag read data (valid on the cycle after req_i)
  output logic [TAG_SIZE-1:0]             rdata_o [NUM_WAYS],

  // Optional: explicit valid-bit clear (invalidate all ways of an index)
  // When set, the array writes an invalid tag regardless of wdata_i.
  input  logic                            invalidate_i
);

  // --------------------------------------------------------------------------
  // Local parameters
  // --------------------------------------------------------------------------

  // Index width (only meaningful when NUM_LINES > 1)
  localparam int unsigned INDEX_W = (NUM_LINES <= 1) ? 1 : $clog2(NUM_LINES);

  // --------------------------------------------------------------------------
  // Storage: one register array per way
  // --------------------------------------------------------------------------
  // Each way has its own storage array of NUM_LINES entries. In ASIC flow this
  // would be a SRAM macro; here we model it with register arrays so the
  // design is synthesizable on FPGA (BRAM-inferred) and simulatable.
  //
  // TODO: For FPGA, infer BRAM via (* ram_style = "block" *) attribute.
  // TODO: Provide a parameterized SRAM wrapper for ASIC targets.

  logic [TAG_SIZE-1:0] tag_storage [NUM_WAYS][NUM_LINES];

  // --------------------------------------------------------------------------
  // Reset / Initialization
  // --------------------------------------------------------------------------
  // All valid bits are cleared on reset. Tag bits are don't-care when
  // valid=0 but we clear them to 0 for determinism in simulation.
  //
  // TODO: For large caches, replace the for-loop reset with a sequential
  //       invalidation FSM (see rvp_cache_flush.sv) to keep reset path
  //       timing clean. The for-loop below is acceptable for small caches
  //       (<=256 lines) typical of this project.

  initial begin
    for (int w = 0; w < NUM_WAYS; w++) begin
      for (int l = 0; l < NUM_LINES; l++) begin
        tag_storage[w][l] = '0;
      end
    end
  end

  // Synthesis-friendly reset (covers non-simulation flows)
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Synchronous clear of all entries on async reset assertion edge.
      // Synthesis tools will convert this to a reset-aware RAM.
      for (int w = 0; w < NUM_WAYS; w++) begin
        for (int l = 0; l < NUM_LINES; l++) begin
          tag_storage[w][l] <= '0;
        end
      end
    end else begin
      // Per-way synchronous write
      for (int w = 0; w < NUM_WAYS; w++) begin
        if (req_i[w] && write_i) begin
          if (invalidate_i) begin
            // Force valid=0 on invalidate regardless of wdata
            tag_storage[w][addr_i[INDEX_W-1:0]] <= '0;
          end else begin
            tag_storage[w][addr_i[INDEX_W-1:0]] <= wdata_i;
          end
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // Asynchronous read (combinational mux on the registered index)
  // --------------------------------------------------------------------------
  // Output of the currently addressed line is presented combinationally so
  // the cache controller can compare tags in the next pipeline stage.
  //
  // TODO: If timing is tight, register the read data and add a read-enable.
  //       ibex uses a synchronous-read SRAM model; choose based on target.

  for (genvar w = 0; w < NUM_WAYS; w++) begin : gen_read
    assign rdata_o[w] = tag_storage[w][addr_i[INDEX_W-1:0]];
  end

  // --------------------------------------------------------------------------
  // Assertions
  // --------------------------------------------------------------------------
  // TODO: Add SV assertions:
  //   - req_i is one-hot when write_i=1 (only one way written per cycle)
  //   - addr_i in range when req_i is set

`ifndef SYNTHESIS
  // synthesis translate_off
  // Write-onehot check
  always @(posedge clk_i) begin
    if (write_i && (|req_i) && ($countones(req_i) > 1)) begin
      $error("rvp_cache_tag_array: multiple ways written in same cycle: %b", req_i);
    end
  end
  // synthesis translate_on
`endif

endmodule
