/**
 * rvp_wb_stage.sv - RVP Writeback Stage
 *
 * 写回阶段，负责将执行结果或内存数据写回寄存器堆。
 * 参考ibex_wb_stage.sv的设计。
 *
 * 主要功能:
 *   1. 结果多路选择 - 从ALU结果、内存数据、PC+4、CSR数据中选择写回值
 *   2. 写回使能控制 - 控制寄存器堆写使能
 *   3. 目标寄存器地址传递 - 传递rd地址到寄存器堆
 *   4. 前递数据输出 - 将写回数据输出到前递单元
 *
 * 写回数据来源 (wb_src_e):
 *   WB_ALU  - ALU计算结果
 *   WB_MEM  - 内存加载(Load)数据
 *   WB_PC4  - PC+4 (JAL/JALR的返回地址)
 *   WB_CSR  - CSR读数据
 */

`include "rvp_config.svh"

module rvp_wb_stage import rvp_pkg::*; (
    // ==========================================================================
    // 时钟与复位
    // ==========================================================================
    input  logic              clk_i,           // 时钟
    input  logic              rst_ni,          // 异步低复位

    // ==========================================================================
    // 来自MEM阶段的输入
    // ==========================================================================
    input  wb_src_e           wb_src_i,        // 写回数据源选择
    input  logic [31:0]       alu_result_i,    // ALU结果
    input  logic [31:0]       mem_rdata_i,     // 内存加载数据
    input  logic [31:0]       pc4_i,           // PC+4 (返回地址)
    input  logic [31:0]       csr_rdata_i,     // CSR读数据
    input  logic [REG_ADDR_W-1:0] rd_addr_i,   // 目标寄存器地址
    input  logic              rf_we_i,         // 寄存器写使能 (来自控制信号)

    // ==========================================================================
    // 流水线控制信号
    // ==========================================================================
    input  logic              stall_i,         // 流水线停顿
    input  logic              flush_i,         // 流水线刷新

    // ==========================================================================
    // 输出到寄存器堆
    // ==========================================================================
    output logic [REG_ADDR_W-1:0] rd_addr_o,   // 目标寄存器地址
    output logic [31:0]       rd_wdata_o,      // 写回数据
    output logic              rf_we_o,         // 寄存器写使能

    // ==========================================================================
    // 前递输出 (到前递单元)
    // ==========================================================================
    output logic [31:0]       wb_forward_data_o, // 写回数据(前递用)
    output logic              wb_valid_o        // 写回有效
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号声明
  // ==========================================================================

  // MEM/WB 流水线寄存器
  wb_src_e           wb_src_q;       // 写回源寄存器
  logic [31:0]        alu_result_q;    // ALU结果寄存器
  logic [31:0]        mem_rdata_q;     // 内存数据寄存器
  logic [31:0]        pc4_q;           // PC+4寄存器
  logic [31:0]        csr_rdata_q;     // CSR数据寄存器
  logic [REG_ADDR_W-1:0] rd_addr_q;    // rd地址寄存器
  logic               rf_we_q;         // 写使能寄存器

  // 写回多路选择结果
  logic [31:0]        wb_data;         // 选择后的写回数据

  // ==========================================================================
  // MEM/WB 流水线寄存器
  // ==========================================================================
  // TODO: 锁存MEM阶段的数据到WB阶段
  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     wb_src_q     <= WB_ALU;
  //     alu_result_q  <= 32'b0;
  //     mem_rdata_q   <= 32'b0;
  //     pc4_q         <= 32'b0;
  //     csr_rdata_q    <= 32'b0;
  //     rd_addr_q     <= 5'b0;
  //     rf_we_q       <= 1'b0;
  //   end else if (flush_i) begin
  //     // Flush: 清除写使能
  //     rf_we_q       <= 1'b0;
  //   end else if (!stall_i) begin
  //     // 正常: 锁存数据
  //     wb_src_q     <= wb_src_i;
  //     alu_result_q  <= alu_result_i;
  //     mem_rdata_q   <= mem_rdata_i;
  //     pc4_q         <= pc4_i;
  //     csr_rdata_q    <= csr_rdata_i;
  //     rd_addr_q     <= rd_addr_i;
  //     rf_we_q       <= rf_we_i;
  //   end
  // end

  // ==========================================================================
  // 写回多路选择器 (wb_mux)
  // ==========================================================================
  always_comb begin
    wb_data = 32'b0;

    // TODO: 根据wb_src_q选择写回数据
    // unique case (wb_src_q)
    //   WB_ALU: wb_data = alu_result_q;   // ALU结果
    //   WB_MEM: wb_data = mem_rdata_q;    // 内存数据
    //   WB_PC4: wb_data = pc4_q;           // PC+4 (返回地址)
    //   WB_CSR: wb_data = csr_rdata_q;     // CSR读数据
    //   default: wb_data = alu_result_q;   // 默认ALU结果
    // endcase
  end

  // ==========================================================================
  // 输出赋值
  // ==========================================================================

  // 写回地址和数据
  // TODO: assign rd_addr_o  = rd_addr_q;
  // TODO: assign rd_wdata_o = wb_data;

  // 写使能: Flush时禁能，x0不可写
  // TODO: assign rf_we_o = rf_we_q & ~flush_i & (rd_addr_q != 5'b0);

  // 前递数据输出 (到前递单元)
  // TODO: assign wb_forward_data_o = wb_data;
  // TODO: assign wb_valid_o = rf_we_q & ~flush_i;

  // ==========================================================================
  // Load数据对齐 (可选)
  // ==========================================================================
  // 注意: Load数据的符号扩展和字节对齐可在MEM阶段或WB阶段完成
  // 当前设计中在MEM阶段完成，WB阶段直接使用mem_rdata_q

  // ==========================================================================
  // 性能计数 (可选)
  // ==========================================================================
  // TODO: 统计写回的指令数

endmodule
