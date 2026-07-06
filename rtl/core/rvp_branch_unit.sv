// =============================================================================
// rvp_branch_unit.sv — RVP 分支判定单元
// =============================================================================
// 功能：根据译码器的分支标志和 ALU 的比较结果，决定分支是否跳转。
//
// 接口：
//   is_branch_i  : 译码器输出，1=当前是条件分支指令（beq/bne/...）
//   cmp_result_i : ALU 的比较结果（1=分支条件成立）
//   branch_taken_o : 1=分支被采用（PC 跳到分支目标），0=不跳（PC+4）
//
// 工作原理：
//   branch_taken = is_branch_i & cmp_result_i
//
//   只有当前是分支指令 AND 条件成立，才真正跳转。
//   非分支指令（addi/lw/...）的 is_branch_i=0，branch_taken 恒 0，PC 走默认路径。
//
//   这个信号送回 PC 逻辑，PC 逻辑据此决定 next_pc：
//     - branch_taken=1 → 用 PC_BRANCH（分支目标）
//     - branch_taken=0 且 next_pc=PC_BRANCH → 改用 PC_SEQ（分支不跳）
//     - 其它 next_pc 值不受影响（JAL/JALR 照常跳）
// =============================================================================

module rvp_branch_unit (
  input  logic is_branch_i,
  input  logic cmp_result_i,
  output logic branch_taken_o
);

  assign branch_taken_o = is_branch_i & cmp_result_i;

endmodule : rvp_branch_unit
