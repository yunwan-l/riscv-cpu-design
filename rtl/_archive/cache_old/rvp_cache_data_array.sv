/**
 * rvp_cache_data_array.sv - Cache Data Storage Array
 *
 * Parameterized data RAM for set-associative caches. Mirrors the tag array
 * organization but stores cache line data (instruction or data words) instead
 * of tags. One independent read/write port per way.
 *
 * The data width equals the cache line size (LINE_SIZE bits). The cache
 * controller muxes the requested word/byte out of the line externally.
 *
 * Reference: ibex_icache.sv data RAM external interface
 *            (ic_data_req_o / ic_data_wdata_o / ic_data_rdata_i)
 */

module rvp_cache_data_array
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  // Number of ways (associativity)
  parameter int unsigned NUM_WAYS  = 2,
  // Number of lines per way
  parameter int unsigned NUM_LINES = 256,
  // Line width in bits (must equal IC_LINE_SIZE / DC_LINE_SIZE)
  parameter int unsigned LINE_SIZE = 64
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,

  // Per-way request (one-hot when write_i=1, all-ways-on read otherwise)
  input  logic [NUM_WAYS-1:0]             req_i,
  // 1 = write (refill), 0 = read (lookup)
  input  logic                            write_i,
  // Index into the set (shared across all ways)
  input  logic [$clog2(NUM_LINES)-1:0]    addr_i,
  // Line data to write (only meaningful when write_i=1)
  input  logic [LINE_SIZE-1:0]            wdata_i,
  // Per-way read data (valid on the cycle after req_i)
  output logic [LINE_SIZE-1:0]            rdata_o [NUM_WAYS]
);

  // --------------------------------------------------------------------------
  // Local parameters
  // --------------------------------------------------------------------------

  localparam int unsigned INDEX_W = (NUM_LINES <= 1) ? 1 : $clog2(NUM_LINES);

  // --------------------------------------------------------------------------
  // Storage: one register array per way
  // --------------------------------------------------------------------------
  // Each way stores NUM_LINES cache lines. Line width is LINE_SIZE bits.
  //
  // TODO: For FPGA, infer BRAM via (* ram_style = "block" *) attribute.
  // TODO: Provide byte-enable write port for partial-line writes (D-Cache
  //       write-back of sub-line stores). Currently the whole line is written
  //       on refill only.

  logic [LINE_SIZE-1:0] data_storage [NUM_WAYS][NUM_LINES];

  // --------------------------------------------------------------------------
  // Reset / Initialization
  // --------------------------------------------------------------------------
  // Data RAM does not require reset (valid bit lives in tag RAM). We clear
  // to 0 for simulation determinism only; synthesis tools may drop this.
  //
  // TODO: Guard the reset clear behind a parameter RESET_ALL to avoid
  //       large reset fanout on big caches (mirrors ibex ResetAll option).

  initial begin
    for (int w = 0; w < NUM_WAYS; w++) begin
      for (int l = 0; l < NUM_LINES; l++) begin
        data_storage[w][l] = '0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Synchronous write / asynchronous read
  // --------------------------------------------------------------------------
  // Reads are combinational so the cache controller can hit-test in the
  // next pipeline stage without an extra cycle. Writes are synchronous.
  //
  // TODO: Add a write-byte-enable (wbe_i) port for partial line writes.
  //       Current model assumes the whole line is written atomically on
  //       refill. For D-Cache write-back of stores into an existing line
  //       we need byte-granular updates.

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      // Optional reset clear (see note above)
      for (int w = 0; w < NUM_WAYS; w++) begin
        for (int l = 0; l < NUM_LINES; l++) begin
          data_storage[w][l] <= '0;
        end
      end
    end else begin
      for (int w = 0; w < NUM_WAYS; w++) begin
        if (req_i[w] && write_i) begin
          data_storage[w][addr_i[INDEX_W-1:0]] <= wdata_i;
        end
      end
    end
  end

  // Combinational read mux
  for (genvar w = 0; w < NUM_WAYS; w++) begin : gen_read
    assign rdata_o[w] = data_storage[w][addr_i[INDEX_W-1:0]];
  end

  // --------------------------------------------------------------------------
  // Assertions
  // --------------------------------------------------------------------------
  // TODO: Add SV assertions:
  //   - req_i one-hot when write_i=1
  //   - addr_i in range

`ifndef SYNTHESIS
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (write_i && (|req_i) && ($countones(req_i) > 1)) begin
      $error("rvp_cache_data_array: multiple ways written in same cycle: %b", req_i);
    end
  end
  // synthesis translate_on
`endif

endmodule
