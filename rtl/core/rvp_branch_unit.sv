/**
 * rvp_branch_unit.sv - RVP Branch Unit
 *
 * 分支判定单元，根据分支类型和操作数比较结果决定分支是否跳转，
 * 并计算分支目标地址。
 *
 * 支持的分支类型 (RISC-V RV32I):
 *   BRANCH_BEQ  - Branch if Equal (rs1 == rs2)
 *   BRANCH_BNE  - Branch if Not Equal (rs1 != rs2)
 *   BRANCH_BLT  - Branch if Less Than, signed (rs1 < rs2)
 *   BRANCH_BGE  - Branch if Greater or Equal, signed (rs1 >= rs2)
 *   BRANCH_BLTU - Branch if Less Than, unsigned (rs1 < rs2, unsigned)
 *   BRANCH_BGEU - Branch if Greater or Equal, unsigned (rs1 >= rs2, unsigned)
 *
 * 设计要点:
 *   - 使用减法器实现比较 (复用ALU的加法器或独立比较器)
 *   - 分支目标 = PC + 立即数 (B型立即数)
 *   - JALR目标 = rs1 + 立即数 (I型立即数)，最低位清零
 */

`include "rvp_config.svh"

module rvp_branch_unit import rvp_pkg::*; (
    input  logic [31:0]       operand_a_i,      // 操作数A (rs1值)
    input  logic [31:0]       operand_b_i,      // 操作数B (rs2值)
    input  logic [31:0]       pc_i,             // 当前PC (用于分支目标计算)
    input  logic [31:0]       imm_i,            // 立即数 (B型或J型)
    input  branch_type_e      branch_type_i,    // 分支类型
    input  logic              is_jal_i,         // 是否为JAL (无条件跳转)
    input  logic              is_jalr_i,        // 是否为JALR (间接跳转)

    output logic              branch_taken_o,   // 分支跳转信号 (1=跳转)
    output logic [31:0]       branch_target_o   // 分支目标地址
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号声明
  // ==========================================================================

  // 比较结果信号
  logic is_equal;         // A == B
  logic is_less_signed;   // A < B (有符号)
  logic is_less_unsigned; // A < B (无符号)

  // 减法器相关信号 (用于比较)
  logic [32:0] sub_result_ext;  // 减法扩展结果(带借位)
  logic        borrow;          // 借位信号

  // 分支判定结果
  logic branch_condition;   // 条件分支满足

  // ==========================================================================
  // 比较器实现
  // ==========================================================================

  // 相等比较: 使用按位异或后约简
  // TODO: assign is_equal = (operand_a_i == operand_b_i);

  // 减法实现比较: A - B = A + (~B) + 1
  // {33{1'b1}} 用于带借位比较
  // TODO: assign sub_result_ext = {1'b0, operand_a_i} + {1'b0, ~operand_b_i} + 33'd1;
  //       assign borrow = sub_result_ext[32];

  // 有符号小于: 判断符号位和溢出
  // A < B (signed) 当且仅当 (A - B) 的符号位与预期一致
  // 参考: result[31] XOR overflow
  // TODO: assign is_less_signed = (operand_a_i[31] != operand_b_i[31])
  //          ? operand_a_i[31]
  //          : sub_result_ext[31];

  // 无符号小于: 直接看借位
  // A < B (unsigned) 当且仅当 A - B 产生借位
  // TODO: assign is_less_unsigned = ~borrow;

  // ==========================================================================
  // 分支条件判定
  // ==========================================================================
  always_comb begin
    branch_condition = 1'b0;

    // TODO: 根据branch_type_i判定条件分支是否满足
    // unique case (branch_type_i)
    //   BRANCH_BEQ:  branch_condition = is_equal;
    //   BRANCH_BNE:  branch_condition = ~is_equal;
    //   BRANCH_BLT:  branch_condition = is_less_signed;
    //   BRANCH_BGE:  branch_condition = ~is_less_signed;
    //   BRANCH_BLTU: branch_condition = is_less_unsigned;
    //   BRANCH_BGEU: branch_condition = ~is_less_unsigned;
    //   BRANCH_NONE: branch_condition = 1'b0;
    //   default:     branch_condition = 1'b0;
    // endcase
  end

  // ==========================================================================
  // 分支跳转决策
  // ==========================================================================

  // 无条件跳转(JAL/JALR)或条件分支满足
  // TODO: assign branch_taken_o = is_jal_i | is_jalr_i | branch_condition;

  // ==========================================================================
  // 分支目标地址计算
  // ==========================================================================
  always_comb begin
    branch_target_o = 32'b0;

    // TODO: 根据跳转类型计算目标地址
    // if (is_jalr_i) begin
    //   // JALR: 目标 = (rs1 + imm) & ~1 (最低位清零)
    //   branch_target_o = (operand_a_i + imm_i) & ~32'b1;
    // end else begin
    //   // JAL / 条件分支: 目标 = PC + imm
    //   branch_target_o = pc_i + imm_i;
    // end
  end

  // ==========================================================================
  // 断言 (可选)
  // ==========================================================================
  // TODO: 验证分支类型合法性
  // TODO: 验证JALR目标地址对齐

endmodule
