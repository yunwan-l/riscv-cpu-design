/**
 * rvp_icache.sv - Instruction Cache (Minimal Stub)
 *
 * When RVP_ICACHE_ENABLE=0, this module is not instantiated.
 * This stub provides the minimum interface for compilation.
 * Full implementation is a Phase 3 extension item.
 */

module rvp_icache
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  parameter bit          ICacheECC    = 1'b0,
  parameter int unsigned NUM_FB       = 4,
  parameter int unsigned BUS_LATENCY  = 2
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          ready_i,
  output logic          valid_o,
  output logic [31:0]   rdata_o,
  output logic [31:0]   addr_o,
  output logic          err_o,
  input  logic          req_i,
  input  logic          branch_i,
  input  logic [31:0]   addr_i,
  output logic          req_o,
  input  logic          gnt_i,
  output logic [31:0]   bus_addr_o,
  input  logic [31:0]   bus_rdata_i,
  input  logic          bus_err_i,
  input  logic          bus_rvalid_i,
  output logic          ic_tag_req_o,
  output logic          ic_tag_write_o,
  output logic [IC_INDEX_W-1:0] ic_tag_addr_o,
  output logic [IC_TAG_SIZE-1:0] ic_tag_wdata_o,
  input  logic [IC_TAG_SIZE-1:0] ic_tag_rdata_i [IC_NUM_WAYS],
  output logic          ic_data_req_o,
  output logic          ic_data_write_o,
  output logic [IC_INDEX_W-1:0] ic_data_addr_o,
  output logic [IC_LINE_SIZE-1:0] ic_data_wdata_o,
  input  logic [IC_LINE_SIZE-1:0] ic_data_rdata_i [IC_NUM_WAYS],
  output logic          flush_done_o,
  input  logic          flush_i,
  input  logic          stats_if_req_i,
  output logic          stats_hit_o,
  output logic          stats_miss_o
);

  // Stub: all outputs tied to inactive
  assign valid_o        = 1'b0;
  assign rdata_o        = 32'b0;
  assign addr_o         = 32'b0;
  assign err_o          = 1'b0;
  assign req_o          = 1'b0;
  assign bus_addr_o     = 32'b0;
  assign ic_tag_req_o   = 1'b0;
  assign ic_tag_write_o = 1'b0;
  assign ic_tag_addr_o  = '0;
  assign ic_tag_wdata_o = '0;
  assign ic_data_req_o  = 1'b0;
  assign ic_data_write_o = 1'b0;
  assign ic_data_addr_o = '0;
  assign ic_data_wdata_o = '0;
  assign flush_done_o   = 1'b0;
  assign stats_hit_o    = 1'b0;
  assign stats_miss_o   = 1'b0;

endmodule
