// =============================================================================
// rvp_multdiv.sv — RVP M 扩展乘除法单元
// =============================================================================
// 功能：执行 RISC-V M 扩展的 8 条指令（MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU）
//
// 接口：
//   op_i       : 乘除法操作类型（multdiv_op_e）
//   operand_a_i: rs1（32 位）
//   operand_b_i: rs2（32 位）
//   result_o   : 运算结果（32 位）
//
// 设计要点：
//   1. 纯组合逻辑（单周期）。乘法用 * 操作符，FPGA 上映射到 DSP 乘法器。
//   2. 除法用 / 和 % 操作符。仿真没问题；FPGA 综合时 Vivado 会推断除法器
//      （可能占用较多资源或降低频率，教学项目可接受）。
//   3. 特殊情况（RISC-V 规范规定）：
//      - 除以 0：DIV → -1（全1），DIVU → 0xFFFFFFFF，REM/REMU → 被除数 rs1
//      - 有符号溢出（-2^31 / -1）：DIV → -2^31（被除数本身），REM → 0
//   4. 乘法的高位运算需要正确处理有符号/无符号：
//      - MULH  : signed × signed
//      - MULHSU: signed × unsigned（rs1 符号扩展，rs2 零扩展）
//      - MULHU : unsigned × unsigned
// =============================================================================

module rvp_multdiv (
  input  rvp_pkg::multdiv_op_e op_i,
  input  logic [31:0]          operand_a_i,
  input  logic [31:0]          operand_b_i,
  output logic [31:0]          result_o
);

  import rvp_pkg::*;

  // -------------------------------------------------------------------------
  // 乘法：扩展到 64 位再相乘
  // -------------------------------------------------------------------------
  // 有符号扩展
  logic signed [63:0] a_s, b_s;
  // 无符号扩展
  logic        [63:0] a_u, b_u;
  // MULHSU 专用：rs1 有符号，rs2 无符号
  logic signed [63:0] a_s_ext;
  logic        [63:0] b_u_ext;

  assign a_s     = $signed(operand_a_i);           // 符号扩展到 64 位
  assign b_s     = $signed(operand_b_i);
  assign a_u     = {32'b0, operand_a_i};           // 零扩展到 64 位
  assign b_u     = {32'b0, operand_b_i};
  assign a_s_ext = $signed(operand_a_i);           // 有符号
  assign b_u_ext = {32'b0, operand_b_i};           // 无符号

  // 64 位乘积
  logic signed [63:0] prod_ss;   // signed × signed
  logic signed [63:0] prod_su;   // signed × unsigned
  logic        [63:0] prod_uu;   // unsigned × unsigned

  assign prod_ss = a_s * b_s;
  assign prod_su = a_s_ext * $signed(b_u_ext);
  assign prod_uu = a_u * b_u;

  // -------------------------------------------------------------------------
  // 除法/取余
  // -------------------------------------------------------------------------
  logic signed [31:0] a_div_s, b_div_s;
  logic        [31:0] a_div_u, b_div_u;

  assign a_div_s = $signed(operand_a_i);
  assign b_div_s = $signed(operand_b_i);
  assign a_div_u = operand_a_i;
  assign b_div_u = operand_b_i;

  // 特殊情况标志
  logic div_by_zero_s, div_by_zero_u;
  logic overflow_s;  // -2^31 / -1

  assign div_by_zero_s = (operand_b_i == 32'b0);
  assign div_by_zero_u = (operand_b_i == 32'b0);
  assign overflow_s    = (operand_a_i == 32'h80000000) && (operand_b_i == 32'hFFFFFFFF);

  // -------------------------------------------------------------------------
  // 结果选择
  // -------------------------------------------------------------------------
  always_comb begin
    unique case (op_i)
      // --- 乘法 ---
      MD_MUL: begin
        // 低 32 位，有符号×有符号（但低 32 位对所有符号约定都一样）
        result_o = prod_ss[31:0];
      end
      MD_MULH: begin
        // 高 32 位，有符号×有符号
        result_o = prod_ss[63:32];
      end
      MD_MULHSU: begin
        // 高 32 位，有符号×无符号
        result_o = prod_su[63:32];
      end
      MD_MULHU: begin
        // 高 32 位，无符号×无符号
        result_o = prod_uu[63:32];
      end
      // --- 除法 ---
      MD_DIV: begin
        // 有符号除法，处理特殊情
        if (div_by_zero_s) begin
          result_o = 32'hFFFFFFFF;           // x / 0 = -1
        end else if (overflow_s) begin
          result_o = 32'h80000000;           // -2^31 / -1 = -2^31（溢出）
        end else begin
          result_o = a_div_s / b_div_s;
        end
      end
      MD_DIVU: begin
        // 无符号除法
        if (div_by_zero_u) begin
          result_o = 32'hFFFFFFFF;           // x / 0 = 2^32 - 1
        end else begin
          result_o = a_div_u / b_div_u;
        end
      end
      // --- 取余 ---
      MD_REM: begin
        // 有符号取余
        if (div_by_zero_s) begin
          result_o = operand_a_i;            // x % 0 = x
        end else if (overflow_s) begin
          result_o = 32'h00000000;           // -2^31 % -1 = 0
        end else begin
          result_o = a_div_s % b_div_s;
        end
      end
      MD_REMU: begin
        // 无符号取余
        if (div_by_zero_u) begin
          result_o = operand_a_i;            // x % 0 = x
        end else begin
          result_o = a_div_u % b_div_u;
        end
      end
      default: result_o = 32'b0;
    endcase
  end

endmodule : rvp_multdiv
