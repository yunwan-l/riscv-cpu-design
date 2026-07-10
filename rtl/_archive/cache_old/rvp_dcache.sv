/**
 * rvp_dcache.sv - Data Cache (Minimal Stub)
 *
 * When RVP_DCACHE_ENABLE=0, this module is not instantiated.
 * This stub provides the minimum interface for compilation.
 * Full implementation is a Phase 3 extension item.
 */

module rvp_dcache
  import rvp_cache_pkg::*;
  import rvp_pkg::*;
#(
  parameter bit          DCacheECC    = 1'b0,
  parameter int unsigned NUM_FB       = 4,
  parameter int unsigned BUS_LATENCY  = 2
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          core_req_i,
  input  logic          core_we_i,
  input  logic [3:0]    core_be_i,
  input  logic [31:0]   core_addr_i,
  input  logic [31:0]   core_wdata_i,
  output logic          core_rvalid_o,
  output logic [31:0]   core_rdata_o,
  output logic          core_err_o,
  output logic          req_o,
  input  logic          gnt_i,
  output logic [31:0]   bus_addr_o,
  output logic          bus_we_o,
  output logic [3:0]    bus_be_o,
  output logic [31:0]   bus_wdata_o,
  input  logic [31:0]   bus_rdata_i,
  input  logic          bus_err_i,
  input  logic          bus_rvalid_i,
  output logic          dc_tag_req_o,
  output logic          dc_tag_write_o,
  output logic [DC_INDEX_W-1:0] dc_tag_addr_o,
  output logic [DC_TAG_SIZE-1:0] dc_tag_wdata_o,
  input  logic [DC_TAG_SIZE-1:0] dc_tag_rdata_i [DC_NUM_WAYS],
  output logic          dc_data_req_o,
  output logic          dc_data_write_o,
  output logic [DC_INDEX_W-1:0] dc_data_addr_o,
  output logic [DC_LINE_SIZE-1:0] dc_data_wdata_o,
  input  logic [DC_LINE_SIZE-1:0] dc_data_rdata_i [DC_NUM_WAYS],
  output logic          flush_done_o,
  input  logic          flush_i,
  input  logic          stats_dreq_i,
  input  logic          stats_dwe_i,
  output logic          stats_hit_o,
  output logic          stats_miss_o
);

  assign core_rvalid_o  = 1'b0;
  assign core_rdata_o   = 32'b0;
  assign core_err_o     = 1'b0;
  assign req_o          = 1'b0;
  assign bus_addr_o     = 32'b0;
  assign bus_we_o       = 1'b0;
  assign bus_be_o       = 4'b0;
  assign bus_wdata_o    = 32'b0;
  assign dc_tag_req_o   = 1'b0;
  assign dc_tag_write_o = 1'b0;
  assign dc_tag_addr_o  = '0;
  assign dc_tag_wdata_o = '0;
  assign dc_data_req_o  = 1'b0;
  assign dc_data_write_o = 1'b0;
  assign dc_data_addr_o = '0;
  assign dc_data_wdata_o = '0;
  assign flush_done_o   = 1'b0;
  assign stats_hit_o    = 1'b0;
  assign stats_miss_o   = 1'b0;

endmodule
