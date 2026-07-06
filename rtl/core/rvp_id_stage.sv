/**
 * rvp_id_stage.sv - RVP Instruction Decode Stage
 *
 * 译码阶段，负责指令译码、寄存器读取和立即数生成。
 *
 * 主要功能:
 *   1. 指令译码 - 调用rvp_decoder生成控制信号
 *   2. 寄存器读取 - 调用rvp_register_file读取rs1和rs2
 *   3. 立即数生成 - 调用rvp_imm_generator生成立即数
 *   4. 前递数据选择 - 根据前递信号选择数据源
 *
 * 内部子模块:
 *   - rvp_decoder       : 指令译码器
 *   - rvp_register_file : 寄存器堆
 *   - rvp_imm_generator : 立即数生成器
 */

`include "rvp_config.svh"

module rvp_id_stage import rvp_pkg::*; #(
    parameter bit RV32E = 1'b0
) (
    input  logic              clk_i,
    input  logic              rst_ni,

    // 来自IF阶段的输入
    input  logic              instr_valid_i,
    input  logic [31:0]       instr_i,
    input  logic [31:0]       pc_i,
    input  logic              instr_fetch_err_i,

    // 寄存器堆写回接口 (来自WB阶段)
    input  logic [REG_ADDR_W-1:0] wb_rd_addr_i,
    input  logic [31:0]       wb_wdata_i,
    input  logic              wb_rf_we_i,

    // 输出到EX阶段
    output ctrl_signals_t    ctrl_signals_o,
    output logic [31:0]       rs1_rdata_o,
    output logic [31:0]       rs2_rdata_o,
    output logic [31:0]       imm_o,
    output logic [31:0]       pc_o,
    output logic [REG_ADDR_W-1:0] rs1_addr_o,
    output logic [REG_ADDR_W-1:0] rs2_addr_o,
    output logic [REG_ADDR_W-1:0] rd_addr_o,
    output logic              instr_valid_o,

    // 异常/特殊指令输出
    output logic              illegal_insn_o,
    output logic              ecall_insn_o,
    output logic              ebreak_insn_o,
    output logic              mret_insn_o,
    output logic              wfi_insn_o,

    // 前递输入 (条件编译)
`ifdef RVP_FORWARDING
    input  forward_sel_e     forward_a_i,
    input  forward_sel_e     forward_b_i,
    input  logic [31:0]       forward_a_data_i,
    input  logic [31:0]       forward_b_data_i,
`endif

    // 流水线控制
    input  logic              stall_i,
    input  logic              flush_i
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号
  // ==========================================================================

  // IF/ID流水线寄存器
  logic [31:0]       instr_q;
  logic [31:0]       pc_q;
  logic              instr_valid_q;

  // 译码器输出
  ctrl_signals_t     ctrl_signals;
  logic [REG_ADDR_W-1:0] rs1_addr;
  logic [REG_ADDR_W-1:0] rs2_addr;
  logic [REG_ADDR_W-1:0] rd_addr;
  imm_type_e         imm_type;
  logic              illegal_insn;
  logic              ecall_insn;
  logic              ebreak_insn;
  logic              mret_insn;
  logic              wfi_insn;

  // 寄存器堆输出
  logic [31:0]       rf_rdata_a;
  logic [31:0]       rf_rdata_b;

  // 立即数输出
  logic [31:0]       imm;

  // 前递后的数据
  logic [31:0]       rs1_rdata_fwd;
  logic [31:0]       rs2_rdata_fwd;

  // ==========================================================================
  // IF/ID 流水线寄存器
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_q       <= 32'h00000013;  // NOP
      pc_q          <= 32'h0;
      instr_valid_q <= 1'b0;
    end else if (flush_i) begin
      instr_q       <= 32'h00000013;  // NOP
      instr_valid_q <= 1'b0;
    end else if (!stall_i) begin
      instr_q       <= instr_i;
      pc_q          <= pc_i;
      instr_valid_q <= instr_valid_i;
    end
  end

  // ==========================================================================
  // 指令译码器实例化
  // ==========================================================================
  rvp_decoder #(
    .RV32E (RV32E)
  ) decoder_inst (
    .instr_i         (instr_q),
    .illegal_c_insn_i(1'b0),
    .ctrl_signals_o  (ctrl_signals),
    .rs1_addr_o      (rs1_addr),
    .rs2_addr_o      (rs2_addr),
    .rd_addr_o       (rd_addr),
    .imm_type_o      (imm_type),
    .illegal_insn_o  (illegal_insn),
    .ecall_insn_o    (ecall_insn),
    .ebreak_insn_o   (ebreak_insn),
    .mret_insn_o     (mret_insn),
    .wfi_insn_o      (wfi_insn)
  );

  // ==========================================================================
  // 立即数生成器实例化
  // ==========================================================================
  rvp_imm_generator imm_gen_inst (
    .instr_i    (instr_q),
    .imm_type_i (imm_type),
    .imm_o      (imm)
  );

  // ==========================================================================
  // 寄存器堆实例化
  // ==========================================================================
  rvp_register_file #(
    .RV32E     (RV32E),
    .DataWidth (REG_DATA_W)
  ) register_file_inst (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .test_en_i       (1'b0),
    .dummy_instr_id_i(1'b0),
    .dummy_instr_wb_i(1'b0),
    .raddr_a_i       (rs1_addr),
    .rdata_a_o       (rf_rdata_a),
    .raddr_b_i       (rs2_addr),
    .rdata_b_o       (rf_rdata_b),
    .waddr_a_i       (wb_rd_addr_i),
    .wdata_a_i       (wb_wdata_i),
    .we_a_i          (wb_rf_we_i)
  );

  // ==========================================================================
  // 前递数据选择 (条件编译)
  // ==========================================================================
`ifdef RVP_FORWARDING
  always_comb begin
    unique case (forward_a_i)
      FWD_EX_MEM: rs1_rdata_fwd = forward_a_data_i;
      FWD_MEM_WB: rs1_rdata_fwd = forward_a_data_i;
      default:    rs1_rdata_fwd = rf_rdata_a;
    endcase
  end

  always_comb begin
    unique case (forward_b_i)
      FWD_EX_MEM: rs2_rdata_fwd = forward_b_data_i;
      FWD_MEM_WB: rs2_rdata_fwd = forward_b_data_i;
      default:    rs2_rdata_fwd = rf_rdata_b;
    endcase
  end
`else
  assign rs1_rdata_fwd = rf_rdata_a;
  assign rs2_rdata_fwd = rf_rdata_b;
`endif

  // ==========================================================================
  // 输出赋值
  // ==========================================================================
  assign ctrl_signals_o = ctrl_signals;
  assign rs1_rdata_o    = rs1_rdata_fwd;
  assign rs2_rdata_o    = rs2_rdata_fwd;
  assign imm_o          = imm;
  assign pc_o           = pc_q;
  assign rs1_addr_o     = rs1_addr;
  assign rs2_addr_o     = rs2_addr;
  assign rd_addr_o      = rd_addr;
  assign instr_valid_o  = instr_valid_q;

  assign illegal_insn_o = illegal_insn;
  assign ecall_insn_o   = ecall_insn;
  assign ebreak_insn_o  = ebreak_insn;
  assign mret_insn_o    = mret_insn;
  assign wfi_insn_o     = wfi_insn;

endmodule
