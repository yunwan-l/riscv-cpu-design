// =============================================================================
// tb_multdiv.sv — M 扩展乘除法单元测试
// =============================================================================
// 测试内容：
//   1. MUL  — 有符号乘法低 32 位
//   2. MULH — 有符号×有符号高 32 位
//   3. MULHSU — 有符号×无符号高 32 位
//   4. MULHU — 无符号×无符号高 32 位
//   5. DIV  — 有符号除法（含除零、溢出）
//   6. DIVU — 无符号除法（含除零）
//   7. REM  — 有符号取余（含除零、溢出）
//   8. REMU — 无符号取余（含除零）
// =============================================================================

`timescale 1ns/1ps

module tb_multdiv;

  import rvp_pkg::*;

  logic [31:0]          a, b;
  logic [31:0]          result;
  rvp_pkg::multdiv_op_e op;

  int errors = 0;
  int tests  = 0;

  rvp_multdiv dut (
    .op_i       (op),
    .operand_a_i(a),
    .operand_b_i(b),
    .result_o   (result)
  );

  // 设置输入 + 等待组合逻辑稳定 + 检查结果
  task automatic test(input rvp_pkg::multdiv_op_e t_op,
                      input [31:0] t_a, input [31:0] t_b,
                      input [31:0] exp, input [255:0] name);
    op = t_op;
    a  = t_a;
    b  = t_b;
    #1;  // 等待 always_comb 稳定
    tests++;
    if (result !== exp) begin
      $display("  [FAIL] %0s : got %h, exp %h", name, result, exp);
      errors++;
    end else begin
      $display("  [ OK ] %0s : %h", name, result);
    end
  endtask

  initial begin
    $display("==========================================================");
    $display(" MultDiv (M-Extension) Testbench Start");
    $display("==========================================================");

    // ===== 1. MUL =====
    $display("--- MUL (signed x signed, low 32 bits) ---");
    test(MD_MUL, 32'd7,    32'd6,    32'd42,        "7*6");
    test(MD_MUL, 32'd100,  32'd200,  32'd20000,     "100*200");
    test(MD_MUL, -32'd3,   32'd5,    -32'd15,       "-3*5");
    test(MD_MUL, -32'd4,   -32'd7,   32'd28,        "-4*-7");
    test(MD_MUL, 32'hFFFF, 32'hFFFF, 32'hFFFE0001,  "0xFFFF*0xFFFF");

    // ===== 2. MULH =====
    $display("--- MULH (signed x signed, high 32 bits) ---");
    test(MD_MULH, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h3FFFFFFF, "max_pos * max_pos");
    test(MD_MULH, -32'd1,       -32'd1,       32'h00000000, "-1 * -1");
    test(MD_MULH, -32'd1,        32'd1,       32'hFFFFFFFF, "-1 * 1");
    test(MD_MULH, 32'h40000000,  32'd2,       32'h00000000, "0x40000000 * 2");

    // ===== 3. MULHSU =====
    $display("--- MULHSU (signed x unsigned, high 32 bits) ---");
    test(MD_MULHSU, -32'd1, 32'hFFFFFFFF, 32'hFFFFFFFF, "-1 * 0xFFFFFFFF(su)");
    test(MD_MULHSU, 32'd1,  32'hFFFFFFFF, 32'h00000000, "1 * 0xFFFFFFFF(su)");

    // ===== 4. MULHU =====
    $display("--- MULHU (unsigned x unsigned, high 32 bits) ---");
    test(MD_MULHU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFE, "0xFFFF..*0xFFFF..");
    test(MD_MULHU, 32'h80000000,  32'd2,        32'h00000001, "0x80000000 * 2");
    test(MD_MULHU, 32'h7FFFFFFF,  32'h7FFFFFFF, 32'h3FFFFFFF, "0x7FFF..*0x7FFF..");

    // ===== 5. DIV =====
    $display("--- DIV (signed division) ---");
    test(MD_DIV, 32'd100,  32'd7,   32'd14,        "100/7");
    test(MD_DIV, -32'd100, 32'd7,   -32'd14,       "-100/7");
    test(MD_DIV, 32'd100,  -32'd7,  -32'd14,       "100/-7");
    test(MD_DIV, -32'd100, -32'd7,  32'd14,        "-100/-7");
    test(MD_DIV, 32'd10,   32'd0,   32'hFFFFFFFF,  "10/0 = -1");
    test(MD_DIV, 32'h80000000, -32'd1, 32'h80000000, "overflow: -2^31/-1");

    // ===== 6. DIVU =====
    $display("--- DIVU (unsigned division) ---");
    test(MD_DIVU, 32'd100,       32'd7,  32'd14,        "100/7");
    test(MD_DIVU, 32'h80000000,  32'd2,  32'h40000000,  "0x80000000/2");
    test(MD_DIVU, 32'hFFFFFFFF,  32'd1,  32'hFFFFFFFF,  "0xFFFFFFFF/1");
    test(MD_DIVU, 32'd10,        32'd0,  32'hFFFFFFFF,  "10/0 = 0xFFFFFFFF");

    // ===== 7. REM =====
    $display("--- REM (signed remainder) ---");
    test(MD_REM, 32'd100,  32'd7,   32'd2,        "100%7");
    test(MD_REM, -32'd100, 32'd7,   -32'd2,       "-100%7");
    test(MD_REM, 32'd100,  -32'd7,  32'd2,        "100%-7");
    test(MD_REM, -32'd100, -32'd7,  -32'd2,       "-100%-7");
    test(MD_REM, 32'd10,   32'd0,   32'd10,       "10%0 = 10");
    test(MD_REM, 32'h80000000, -32'd1, 32'h00000000, "overflow: -2^31%-1 = 0");

    // ===== 8. REMU =====
    $display("--- REMU (unsigned remainder) ---");
    test(MD_REMU, 32'd100,       32'd7,  32'd2,        "100%7");
    test(MD_REMU, 32'h80000000,  32'd3,  32'd2,        "0x80000000%3");
    test(MD_REMU, 32'hFFFFFFFF,  32'd16, 32'h0000000F, "0xFFFFFFFF%16");
    test(MD_REMU, 32'd10,        32'd0,  32'd10,       "10%0 = 10");

    // ===== 汇总 =====
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_multdiv
