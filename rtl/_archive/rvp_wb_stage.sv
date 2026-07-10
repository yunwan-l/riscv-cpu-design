/**
 * rvp_wb_stage.sv - RVP Writeback Stage
 *
 * 写回阶段，负责将执行结果或内存数据写回寄存器堆。
 *
 * 写回数据来源:
 *   WB_ALU  - ALU计算结果
 *   WB_MEM  - 内存加载数据
 *   WB_PC4  - PC+4 (JAL/JALR的返回地址)
 *   WB_CSR  - CSR读数据
 */

`include "rvp_config.svh"

module rvp_wb_stage import rvp_pkg::*; (
    input  logic              clk_i,
    input  logic              rst_ni,

    // 来自MEM阶段的输入
    input  wb_src_e           wb_src_i,
    input  logic [31:0]       alu_result_i,
    input  logic [31:0]       mem_rdata_i,
    input  logic [31:0]       pc4_i,
    input  logic [31:0]       csr_rdata_i,
    input  logic [REG_ADDR_W-1:0] rd_addr_i,
    input  logic              rf_we_i,

    // 流水线控制
    input  logic              stall_i,
    input  logic              flush_i,

    // 输出到寄存器堆
    output logic [REG_ADDR_W-1:0] rd_addr_o,
    output logic [31:0]       rd_wdata_o,
    output logic              rf_we_o,

    // 前递输出
    output logic [31:0]       wb_forward_data_o,
    output logic              wb_valid_o
);

  import rvp_pkg::*;

  // ==========================================================================
  // MEM/WB 流水线寄存器
  // ==========================================================================
  wb_src_e           wb_src_q;
  logic [31:0]        alu_result_q;
  logic [31:0]        mem_rdata_q;
  logic [31:0]        pc4_q;
  logic [31:0]        csr_rdata_q;
  logic [REG_ADDR_W-1:0] rd_addr_q;
  logic               rf_we_q;

  // 写回多路选择结果
  logic [31:0]        wb_data;

  // ==========================================================================
  // MEM/WB 流水线寄存器
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_src_q     <= WB_ALU;
      alu_result_q <= 32'b0;
      mem_rdata_q  <= 32'b0;
      pc4_q        <= 32'b0;
      csr_rdata_q  <= 32'b0;
      rd_addr_q    <= 5'b0;
      rf_we_q      <= 1'b0;
    end else if (flush_i) begin
      rf_we_q      <= 1'b0;
    end else if (!stall_i) begin
      wb_src_q     <= wb_src_i;
      alu_result_q <= alu_result_i;
      mem_rdata_q  <= mem_rdata_i;
      pc4_q        <= pc4_i;
      csr_rdata_q  <= csr_rdata_i;
      rd_addr_q    <= rd_addr_i;
      rf_we_q      <= rf_we_i;
    end
  end

  // ==========================================================================
  // 写回多路选择器
  // ==========================================================================
  always_comb begin
    unique case (wb_src_q)
      WB_ALU: wb_data = alu_result_q;
      WB_MEM: wb_data = mem_rdata_q;
      WB_PC4: wb_data = pc4_q;
      WB_CSR: wb_data = csr_rdata_q;
      default: wb_data = alu_result_q;
    endcase
  end

  // ==========================================================================
  // 输出赋值
  // ==========================================================================

  assign rd_addr_o  = rd_addr_q;
  assign rd_wdata_o = wb_data;

  // 写使能: Flush时禁能，x0不可写
  assign rf_we_o = rf_we_q & ~flush_i & (rd_addr_q != 5'b0);

  // 前递数据输出
  assign wb_forward_data_o = wb_data;
  assign wb_valid_o = rf_we_q & ~flush_i;

endmodule
