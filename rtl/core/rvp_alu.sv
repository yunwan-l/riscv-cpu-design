/**
 * rvp_alu.sv - RVP Arithmetic Logic Unit
 *
 * 完整的ALU实现框架，支持RV32I全部操作以及M扩展（条件编译）。
 * 参考ibex_alu.sv的加法器/比较器/移位器设计。
 *
 * 支持的操作:
 *   - 算术: ADD, SUB
 *   - 逻辑: XOR, OR, AND
 *   - 移位: SLL, SRL, SRA
 *   - 比较: SLT, SLTU
 *   - 传递: LUI (直通立即数)
 *   - M扩展: MUL, MULH, DIV, REM (条件编译)
 *
 * 设计要点:
 *   - 使用单一加法器实现加/减运算，减法通过补码加法实现
 *   - 比较器复用加法器的进位输出
 *   - 算术右移通过符号位填充实现
 *   - M扩展操作在多周期乘除法器中完成
 */

`include "rvp_config.svh"

module rvp_alu import rvp_pkg::*; (
    input  logic [31:0]       operand_a_i,      // ALU操作数A (通常来自rs1或PC)
    input  logic [31:0]       operand_b_i,      // ALU操作数B (通常来自rs2或立即数)
    input  alu_op_e          alu_op_i,         // ALU操作选择信号

    // M扩展相关接口 (条件编译)
`ifdef RVP_RV32M
    input  logic              multdiv_ready_i,  // 乘除法器完成信号
    input  logic [31:0]       multdiv_result_i, // 乘除法结果
    input  logic              multdiv_sel_i,    // 选择乘除法结果
    output logic              mult_en_o,        // 乘法使能
    output logic              div_en_o,         // 除法使能
`endif

    output logic [31:0]       result_o,         // ALU最终结果
    output logic              comparison_result_o, // 比较结果(用于分支)
    output logic              is_equal_result_o    // 相等比较结果(用于分支)
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号声明
  // ==========================================================================

  // 加法器相关信号
  logic [31:0] operand_a_rev;       // 操作数A位反转(用于左移)
  logic [32:0] operand_b_neg;       // 操作数B取反(用于减法)
  logic        adder_op_b_negate;   // 减法控制: 1=取反B
  logic [32:0] adder_in_a;         // 加法器输入A (33位带进位)
  logic [32:0] adder_in_b;         // 加法器输入B (33位带进位)
  logic [33:0] adder_result_ext;    // 加法器扩展结果(含进位)
  logic [31:0] adder_result;        // 加法器结果(32位)

  // 移位器相关信号
  logic [31:0] shift_operand_a;     // 移位器输入
  logic [4:0]  shift_amt;           // 移位量
  logic [31:0] shift_result;        // 移位结果
  logic [31:0] shift_right_result;  // 右移结果
  logic [31:0] shift_left_result;   // 左移结果

  // 比较器相关信号
  logic        is_equal;            // A == B
  logic        is_less_signed;      // A < B (有符号)
  logic        is_less_unsigned;    // A < B (无符号)

  // 位反转辅助信号
  logic [31:0] operand_b_rev;       // 操作数B位反转(用于右移转左移)

  // ==========================================================================
  // 加法器实现 (参考ibex_alu.sv)
  // ==========================================================================

  // 减法/比较时需要将操作数B取反 (补码加法)
  // TODO: 实现adder_op_b_negate逻辑
  //       根据alu_op_i判断是否需要取反B
  //       SUB/SLT/SLTU/分支比较需要取反
  always_comb begin
    adder_op_b_negate = 1'b0;
    // TODO: case (alu_op_i)
    //   ALU_SUB, ALU_SLT, ALU_SLTU: adder_op_b_negate = 1'b1;
    //   default: adder_op_b_negate = 1'b0;
    // endcase
  end

  // 准备加法器输入A (扩展为33位，最低位补1用于进位链)
  // TODO: assign adder_in_a = {operand_a_i, 1'b1};

  // 准备加法器输入B (减法时取反，加法时直通)
  // TODO: assign operand_b_neg = {operand_b_i, 1'b0} ^ {33{1'b1}};
  //       assign adder_in_b = adder_op_b_negate ? operand_b_neg : {operand_b_i, 1'b0};

  // 加法器执行
  // TODO: assign adder_result_ext = adder_in_a + adder_in_b;
  //       assign adder_result = adder_result_ext[32:1];

  // ==========================================================================
  // 比较器实现 (复用加法器结果)
  // ==========================================================================

  // 相等比较
  // TODO: assign is_equal = (operand_a_i == operand_b_i);

  // 有符号小于比较
  // 利用加法器: A + (-B) 的符号位和溢出判断
  // TODO: assign is_less_signed = (~adder_result_ext[33] ^ adder_result_ext[32]);

  // 无符号小于比较
  // TODO: assign is_less_unsigned = ~adder_result_ext[32];

  // 比较结果输出
  // TODO: assign comparison_result_o = ...;
  // TODO: assign is_equal_result_o = is_equal;

  // ==========================================================================
  // 移位器实现
  // ==========================================================================

  // 位反转操作数A (左移转右移的技巧)
  // TODO: 实现 operand_a_rev[k] = operand_a_i[31-k]
  for (genvar k = 0; k < 32; k++) begin : gen_rev_operand_a
    // TODO: assign operand_a_rev[k] = operand_a_i[31-k];
  end

  // 移位量取低5位
  // TODO: assign shift_amt = operand_b_i[4:0];

  // 右移 (逻辑右移)
  // TODO: assign shift_right_result = operand_a_i >> shift_amt;

  // 左移 (通过反转→右移→反转实现)
  // TODO: assign shift_left_result = (operand_a_rev >> shift_amt) 反转;

  // 算术右移 (符号位填充)
  // TODO: assign shift_right_arith = $signed(operand_a_i) >>> shift_amt;

  // ==========================================================================
  // M扩展支持 (条件编译)
  // ==========================================================================
`ifdef RVP_RV32M
  // M扩展使能信号
  // TODO: assign mult_en_o = (alu_op_i == ALU_MUL) || (alu_op_i == ALU_MULH);
  // TODO: assign div_en_o  = (alu_op_i == ALU_DIV) || (alu_op_i == ALU_REM);
`endif

  // ==========================================================================
  // 结果多路选择
  // ==========================================================================
  always_comb begin
    result_o = 32'b0;
    // TODO: 根据alu_op_i选择输出结果
    // unique case (alu_op_i)
    //   ALU_ADD:  result_o = adder_result;
    //   ALU_SUB:  result_o = adder_result;
    //   ALU_XOR:  result_o = operand_a_i ^ operand_b_i;
    //   ALU_OR:   result_o = operand_a_i | operand_b_i;
    //   ALU_AND:  result_o = operand_a_i & operand_b_i;
    //   ALU_SLL:  result_o = shift_left_result;
    //   ALU_SRL:  result_o = shift_right_result;
    //   ALU_SRA:  result_o = shift_right_arith;
    //   ALU_SLT:  result_o = {31'b0, is_less_signed};
    //   ALU_SLTU: result_o = {31'b0, is_less_unsigned};
    //   ALU_LUI:  result_o = operand_b_i;  // 直通立即数
    //   ALU_NOP:  result_o = 32'b0;
    //   default:  result_o = 32'b0;
    // endcase

    // M扩展结果选择
`ifdef RVP_RV32M
    // TODO: if (multdiv_sel_i && multdiv_ready_i) begin
    //         result_o = multdiv_result_i;
    //       end
`endif
  end

  // ==========================================================================
  // 断言 (可选)
  // ==========================================================================
  // TODO: 添加断言检查操作码合法性

endmodule
