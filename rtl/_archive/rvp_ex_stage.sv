/**
 * rvp_ex_stage.sv - RVP Execute Stage
 *
 * 执行阶段，负责ALU运算、分支判定和跳转目标计算。
 *
 * 主要功能:
 *   1. ALU运算 - 执行算术、逻辑、移位等操作
 *   2. 分支判定 - 判定条件分支是否跳转
 *   3. 跳转目标计算 - 计算JAL/JALR/分支目标地址
 *   4. 操作数选择 - 从寄存器值、立即数、PC中选择ALU操作数
 *   5. 前递数据选择 - 根据前递信号选择操作数来源 (条件编译)
 *
 * 内部子模块:
 *   - rvp_alu         : 算术逻辑单元
 *   - rvp_branch_unit : 分支判定单元
 */

`include "rvp_config.svh"

module rvp_ex_stage import rvp_pkg::*; (
    input  logic              clk_i,
    input  logic              rst_ni,

    // 来自ID阶段的输入
    input  ctrl_signals_t    ctrl_signals_i,
    input  logic [31:0]       rs1_rdata_i,
    input  logic [31:0]       rs2_rdata_i,
    input  logic [31:0]       imm_i,
    input  logic [31:0]       pc_i,
    input  logic [REG_ADDR_W-1:0] rs1_addr_i,
    input  logic [REG_ADDR_W-1:0] rs2_addr_i,
    input  logic [REG_ADDR_W-1:0] rd_addr_i,
    input  logic              instr_valid_i,

    // 前递输入 (条件编译)
`ifdef RVP_FORWARDING
    input  forward_sel_e     forward_a_i,
    input  forward_sel_e     forward_b_i,
    input  logic [31:0]       forward_a_data_i,
    input  logic [31:0]       forward_b_data_i,
`endif

    // ALU操作数
    input  alu_op_e           alu_op_i,
    input  logic              alu_src_a_i,
    input  logic              alu_src_b_i,

    // 输出到MEM阶段
    output logic [31:0]       alu_result_o,
    output logic              alu_result_valid_o,
    output logic [31:0]       mem_addr_o,
    output logic [31:0]       mem_wdata_o,
    output logic              mem_req_o,
    output logic              mem_we_o,
    output mem_size_e         mem_size_o,
    output logic [31:0]       pc4_o,
    output logic [REG_ADDR_W-1:0] rd_addr_o,
    output logic              rf_we_o,
    output wb_src_e           wb_src_o,
    output logic              instr_valid_o,

    // 分支输出
    output logic              branch_taken_o,
    output logic [31:0]       branch_target_o,

    // 流水线控制
    input  logic              stall_i,
    input  logic              flush_i
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号
  // ==========================================================================

  // ID/EX流水线寄存器
  ctrl_signals_t      ctrl_signals_q;
  logic [31:0]        rs1_rdata_q;
  logic [31:0]        rs2_rdata_q;
  logic [31:0]        imm_q;
  logic [31:0]        pc_q;
  logic [REG_ADDR_W-1:0] rs1_addr_q;
  logic [REG_ADDR_W-1:0] rs2_addr_q;
  logic [REG_ADDR_W-1:0] rd_addr_q;
  logic               instr_valid_q;

  // ALU操作数
  logic [31:0]        operand_a;
  logic [31:0]        operand_b;
  logic [31:0]        operand_a_fwd;
  logic [31:0]        operand_b_fwd;

  // ALU输出
  logic [31:0]        alu_result;
  logic               alu_comparison;
  logic               alu_is_equal;

  // 分支单元输出
  logic               branch_taken;
  logic [31:0]        branch_target;

  // PC+4
  logic [31:0]        pc_plus4;

  // ==========================================================================
  // ID/EX 流水线寄存器
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_signals_q <= '0;
      rs1_rdata_q    <= 32'b0;
      rs2_rdata_q    <= 32'b0;
      imm_q          <= 32'b0;
      pc_q           <= 32'b0;
      rs1_addr_q     <= 5'b0;
      rs2_addr_q     <= 5'b0;
      rd_addr_q      <= 5'b0;
      instr_valid_q  <= 1'b0;
    end else if (flush_i) begin
      ctrl_signals_q.reg_write <= 1'b0;
      ctrl_signals_q.mem_read  <= 1'b0;
      ctrl_signals_q.mem_write <= 1'b0;
      instr_valid_q            <= 1'b0;
    end else if (!stall_i) begin
      ctrl_signals_q <= ctrl_signals_i;
      rs1_rdata_q    <= rs1_rdata_i;
      rs2_rdata_q    <= rs2_rdata_i;
      imm_q          <= imm_i;
      pc_q           <= pc_i;
      rs1_addr_q     <= rs1_addr_i;
      rs2_addr_q     <= rs2_addr_i;
      rd_addr_q      <= rd_addr_i;
      instr_valid_q  <= instr_valid_i;
    end
  end

  // ==========================================================================
  // 前递多路选择器
  // ==========================================================================
`ifdef RVP_FORWARDING
  always_comb begin
    unique case (forward_a_i)
      FWD_EX_MEM, FWD_MEM_WB, FWD_WB: operand_a_fwd = forward_a_data_i;
      default:                         operand_a_fwd = rs1_rdata_q;
    endcase
  end

  always_comb begin
    unique case (forward_b_i)
      FWD_EX_MEM, FWD_MEM_WB, FWD_WB: operand_b_fwd = forward_b_data_i;
      default:                         operand_b_fwd = rs2_rdata_q;
    endcase
  end
`else
  assign operand_a_fwd = rs1_rdata_q;
  assign operand_b_fwd = rs2_rdata_q;
`endif

  // ==========================================================================
  // ALU操作数选择
  // ==========================================================================

  // 操作数A: rs1值 或 PC
  assign operand_a = ctrl_signals_q.alu_src_a ? pc_q : operand_a_fwd;

  // 操作数B: rs2值 或 立即数
  assign operand_b = ctrl_signals_q.alu_src_b ? imm_q : operand_b_fwd;

  // ==========================================================================
  // ALU实例化
  // ==========================================================================
  rvp_alu alu_inst (
    .operand_a_i        (operand_a),
    .operand_b_i        (operand_b),
    .alu_op_i           (ctrl_signals_q.alu_op),
`ifdef RVP_RV32M
    .multdiv_ready_i    (1'b1),       // TODO: Multi-cycle M extension
    .multdiv_result_i   (32'b0),
    .multdiv_sel_i      (1'b0),
    .mult_en_o          (),
    .div_en_o           (),
`endif
    .result_o           (alu_result),
    .comparison_result_o(alu_comparison),
    .is_equal_result_o  (alu_is_equal)
  );

  // ==========================================================================
  // 分支单元实例化
  // ==========================================================================
  rvp_branch_unit branch_unit_inst (
    .operand_a_i    (operand_a_fwd),
    .operand_b_i    (operand_b_fwd),
    .pc_i           (pc_q),
    .imm_i          (imm_q),
    .branch_type_i  (ctrl_signals_q.branch_type),
    .is_jal_i       (ctrl_signals_q.jump & ~ctrl_signals_q.jalr),
    .is_jalr_i      (ctrl_signals_q.jalr),
    .branch_taken_o (branch_taken),
    .branch_target_o(branch_target)
  );

  // ==========================================================================
  // PC+4 计算
  // ==========================================================================
  assign pc_plus4 = pc_q + 32'd4;

  // ==========================================================================
  // 输出赋值
  // ==========================================================================

  assign alu_result_o       = alu_result;
  // Note: Do NOT gate with ~flush_i here — it creates a combinational loop
  // flush_ex → rf_we_o → ex_reg_write_i → raw_ex_hazard → any_stall → flush_ex
  // The flush clears ctrl_signals_q.reg_write to 0, so rf_we_o is already 0 after flush.
  assign alu_result_valid_o = instr_valid_q;

  assign mem_addr_o  = alu_result;
  assign mem_wdata_o = operand_b_fwd;
  assign mem_req_o   = (ctrl_signals_q.mem_read | ctrl_signals_q.mem_write) & instr_valid_q;
  assign mem_we_o    = ctrl_signals_q.mem_write;
  assign mem_size_o  = ctrl_signals_q.mem_size;

  assign pc4_o = pc_plus4;

  assign rd_addr_o  = rd_addr_q;
  assign rf_we_o    = ctrl_signals_q.reg_write & instr_valid_q;
  assign wb_src_o   = ctrl_signals_q.wb_src;

  assign branch_taken_o  = branch_taken & instr_valid_q;
  assign branch_target_o = branch_target;

  assign instr_valid_o = instr_valid_q;

endmodule
