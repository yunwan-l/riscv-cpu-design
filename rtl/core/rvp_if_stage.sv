/**
 * rvp_if_stage.sv - RVP Instruction Fetch Stage
 *
 * 取指阶段，负责从指令存储器获取指令并管理PC。
 *
 * 主要功能:
 *   1. PC寄存器管理 - 维护当前程序计数器
 *   2. PC下一值计算 - PC+4、分支目标、异常向量
 *   3. 指令获取 - 从I-Cache或直接从存储器获取指令
 *   4. IF/ID流水线寄存器 - 锁存指令和PC
 */

`include "rvp_config.svh"

module rvp_if_stage import rvp_pkg::*; #(
    parameter bit          ICacheEnable    = 1'b0,
    parameter int unsigned ICacheSizeBytes = 4096,
    parameter int unsigned ICacheNumWays   = 2,
    parameter int unsigned ICacheLineSize  = 64
) (
    input  logic              clk_i,
    input  logic              rst_ni,

    input  logic [31:0]       boot_addr_i,
    input  logic [31:0]       pc_src_i,
    input  logic [2:0]        pc_sel_i,
    input  logic              pc_set_i,
    input  logic [2:0]        exc_pc_mux_i,

    // 指令总线接口
    output logic              instr_req_o,
    input  logic              instr_gnt_i,
    input  logic              instr_rvalid_i,
    output logic [31:0]       instr_addr_o,
    input  logic [31:0]       instr_rdata_i,

    // 输出到ID阶段
    output logic [31:0]       instr_rdata_o,
    output logic [31:0]       pc_o,
    output logic              instr_valid_o,
    output logic              instr_fetch_err_o,

    // 流水线控制
    input  logic              stall_i,
    input  logic              flush_i,
    input  logic              debug_req_i
);

  import rvp_pkg::*;

  // ==========================================================================
  // PC选择编码
  // ==========================================================================
  // PC_SEL_BOOT   = 3'd0 - 启动地址
  // PC_SEL_PC4    = 3'd1 - PC+4
  // PC_SEL_BRANCH = 3'd2 - 分支目标
  // PC_SEL_EXC    = 3'd3 - 异常向量

  // ==========================================================================
  // 内部信号
  // ==========================================================================

  logic [31:0] pc_q;
  logic [31:0] pc_d;
  logic [31:0] pc_plus4;

  logic [31:0] instr_q;
  logic [31:0] pc_if_q;
  logic        fetch_valid;

  // ==========================================================================
  // PC+4 计算
  // ==========================================================================
  assign pc_plus4 = pc_q + 32'd4;

  // ==========================================================================
  // PC下一值选择
  // ==========================================================================
  always_comb begin
    unique case (pc_sel_i)
      3'd0: pc_d = boot_addr_i;   // 启动地址
      3'd1: pc_d = pc_plus4;      // PC+4
      3'd2: pc_d = pc_src_i;      // 分支/跳转目标
      3'd3: pc_d = exc_pc_mux_i;  // 异常向量
      default: pc_d = pc_plus4;   // 默认PC+4
    endcase

    if (stall_i) pc_d = pc_q;
    if (flush_i) pc_d = pc_src_i;
  end

  // ==========================================================================
  // PC寄存器
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q <= boot_addr_i;
    end else if (!stall_i) begin
      pc_q <= pc_d;
    end
  end

  // ==========================================================================
  // 取指地址和请求
  // ==========================================================================
  assign instr_addr_o = pc_q;
  assign instr_req_o  = ~stall_i & ~flush_i;

  // 直接取指模式: 从总线获取指令 (I-Cache禁用时)
  assign fetch_valid = instr_rvalid_i;

  // ==========================================================================
  // IF/ID 流水线寄存器
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_q   <= 32'h00000013;   // NOP (ADDI x0, x0, 0)
      pc_if_q   <= 32'h0;
    end else if (flush_i) begin
      instr_q   <= 32'h00000013;   // NOP
      pc_if_q   <= 32'h0;
    end else if (!stall_i) begin
      instr_q   <= instr_rdata_i;
      pc_if_q   <= pc_q;
    end
  end

  // ==========================================================================
  // 输出赋值
  // ==========================================================================
  assign instr_rdata_o    = instr_q;
  assign pc_o             = pc_if_q;
  assign instr_valid_o    = fetch_valid & ~flush_i;
  assign instr_fetch_err_o = 1'b0;

  // ==========================================================================
  // 未使用信号
  // ==========================================================================
  logic unused_pc_set;
  assign unused_pc_set = pc_set_i;

endmodule
