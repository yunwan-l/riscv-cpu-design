// =============================================================================
// rvp_alu.sv — RVP 算术逻辑单元
// =============================================================================
// 功能：根据 alu_op_i 对两个 32 位操作数做运算，输出结果与分支判定。
//
// 接口：
//   alu_op_i      : 操作码（见 rvp_pkg::alu_op_e）
//   operand_a_i   : 操作数 A（通常来自 rs1 或 PC）
//   operand_b_i   : 操作数 B（通常来自 rs2 或立即数）
//   result_o      : 算术/逻辑运算结果，写回寄存器堆
//   cmp_result_o  : 比较结果（1=条件成立），供分支指令决定是否跳转
//
// 覆盖范围：RV32I 全部算术/逻辑/移位/比较 + 6 种分支判定
// （M 扩展的乘除法在后续 rvp_multdiv 模块单独实现，不放在这里）
// =============================================================================

module rvp_alu (
  input  rvp_pkg::alu_op_e  alu_op_i,
  input  logic [31:0]       operand_a_i,
  input  logic [31:0]       operand_b_i,
  output logic [31:0]       result_o,
  output logic              cmp_result_o
);

  import rvp_pkg::*;

  // -------------------------------------------------------------------------
  // 1. 加法 / 减法
  // -------------------------------------------------------------------------
  // 减法用补码实现：a - b = a + (~b) + 1，综合器会识别成同一个加减法器。
  // 这里直接写 + / -，工具自动复用硬件，比手写 ~b+1 更清晰。
  logic [31:0] add_result;
  logic [31:0] sub_result;
  assign add_result = operand_a_i + operand_b_i;
  assign sub_result = operand_a_i - operand_b_i;

  // -------------------------------------------------------------------------
  // 2. 比较逻辑
  // -------------------------------------------------------------------------
  // 三种基础比较，分支与 SLT 共用：
  //   is_equal          : a == b                 （BEQ/BNE 用）
  //   is_less_signed    : $signed(a) < $signed(b)（BLT/BGE/SLT 用）
  //   is_less_unsigned  : a < b                  （BLTU/BGEU/SLTU 用）
  //
  // 注意：$signed() 只改变"如何解读"这 32 位，不改位宽。综合后会用符号位
  // 做有符号比较，这是标准写法，Vivado/ModelSim 都能正确处理。
  logic is_equal;
  logic is_less_signed;
  logic is_less_unsigned;
  assign is_equal         = (operand_a_i == operand_b_i);
  assign is_less_signed   = ($signed(operand_a_i) < $signed(operand_b_i));
  assign is_less_unsigned = (operand_a_i < operand_b_i);

  // -------------------------------------------------------------------------
  // 3. 移位
  // -------------------------------------------------------------------------
  // RISC-V 规定移位量只看 rs2/imm 的低 5 位（32 位数据）。
  //   <<  逻辑左移（低位补 0）
  //   >>  逻辑右移（高位补 0）        —— SRL
  //   >>> 算术右移（高位补符号位）    —— SRA，需把操作数声明为 signed
  logic [4:0] shamt;
  assign shamt = operand_b_i[4:0];

  // -------------------------------------------------------------------------
  // 4. 分支判定结果 cmp_result_o
  // -------------------------------------------------------------------------
  // 分支指令只关心"条件成不成立"，不写回寄存器，所以走 cmp_result_o。
  // 注意 GE/GEB 是 LT 的反：a>=b 等价于 !(a<b)，复用 is_less 即可。
  always_comb begin
    unique case (alu_op_i)
      ALU_EQ:  cmp_result_o = is_equal;
      ALU_NE:  cmp_result_o = ~is_equal;
      ALU_LT:  cmp_result_o = is_less_signed;
      ALU_GE:  cmp_result_o = ~is_less_signed;
      ALU_LTU: cmp_result_o = is_less_unsigned;
      ALU_GEU: cmp_result_o = ~is_less_unsigned;
      default: cmp_result_o = 1'b0;
    endcase
  end

  // -------------------------------------------------------------------------
  // 5. 主结果 result_o（多路选择）
  // -------------------------------------------------------------------------
  // unique case 告诉综合器：这些分支互斥，便于优化成多路选择器。
  // 算术右移 SRA 必须用 $signed >>> 才会补符号位；若用 >> 则补 0（错）。
  always_comb begin
    unique case (alu_op_i)
      ALU_ADD:  result_o = add_result;
      ALU_SUB:  result_o = sub_result;
      ALU_SLL:  result_o = operand_a_i << shamt;
      ALU_SRL:  result_o = operand_a_i >> shamt;
      ALU_SRA:  result_o = $signed(operand_a_i) >>> shamt;
      ALU_SLT:  result_o = {31'b0, is_less_signed};
      ALU_SLTU: result_o = {31'b0, is_less_unsigned};
      ALU_XOR:  result_o = operand_a_i ^ operand_b_i;
      ALU_OR:   result_o = operand_a_i | operand_b_i;
      ALU_AND:  result_o = operand_a_i & operand_b_i;
      default:  result_o = 32'b0;   // 分支指令的 result 不用，置 0
    endcase
  end

endmodule : rvp_alu
