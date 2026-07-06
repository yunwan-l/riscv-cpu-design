// =============================================================================
// tb_alu.sv — ALU 单元测试
// =============================================================================
// 用法（ModelSim 命令行）：
//   vlib work
//   vlog -sv ../rtl/rvp_pkg.sv ../rtl/core/rvp_alu.sv tb_alu.sv
//   vsim -c -do "run -all; quit" tb_alu
//
// 测试策略：对每个 ALU 操作用几组有代表性的向量（含边界值、负数），
// 自动比对期望值，统计错误数，最后打印 PASS / FAIL 汇总。
// =============================================================================

`timescale 1ns/1ps

module tb_alu;

  import rvp_pkg::*;

  // --- DUT 信号 ---
  alu_op_e     op;
  logic [31:0] a, b;
  logic [31:0] result;
  logic        cmp;

  // --- 错误计数 ---
  int errors = 0;
  int tests  = 0;

  // --- 例化待测模块 ---
  rvp_alu dut (
    .alu_op_i     (op),
    .operand_a_i  (a),
    .operand_b_i  (b),
    .result_o     (result),
    .cmp_result_o (cmp)
  );

  // -------------------------------------------------------------------------
  // 检查任务：比对 result_o（用于算术逻辑指令）
  // -------------------------------------------------------------------------
  task automatic chk_res(input [31:0] exp, input [255:0] name);
    tests++;
    if (result !== exp) begin
      $display("  [FAIL] %0s : a=%h b=%h => got %h, exp %h", name, a, b, result, exp);
      errors++;
    end else begin
      $display("  [ OK ] %0s : a=%h b=%h => %h", name, a, b, result);
    end
  endtask

  // -------------------------------------------------------------------------
  // 检查任务：比对 cmp_result_o（用于分支指令）
  // -------------------------------------------------------------------------
  task automatic chk_cmp(input logic exp, input [255:0] name);
    tests++;
    if (cmp !== exp) begin
      $display("  [FAIL] %0s : a=%h b=%h => got %b, exp %b", name, a, b, cmp, exp);
      errors++;
    end else begin
      $display("  [ OK ] %0s : a=%h b=%h => %b", name, a, b, cmp);
    end
  endtask

  // -------------------------------------------------------------------------
  // 主测试流程
  // -------------------------------------------------------------------------
  initial begin
    $display("==========================================================");
    $display(" ALU Testbench Start");
    $display("==========================================================");

    // ===== ADD =====
    $display("--- ADD ---");
    op = ALU_ADD;  a = 32'd3;       b = 32'd5;       #10; chk_res(32'd8,    "ADD 3+5");
                   a = 32'h7FFFFFFF; b = 32'd1;       #10; chk_res(32'h80000000, "ADD overflow");
                   a = 32'hFFFFFFFE; b = 32'd2;       #10; chk_res(32'd0,    "ADD wrap");

    // ===== SUB =====
    $display("--- SUB ---");
    op = ALU_SUB;  a = 32'd10;      b = 32'd3;       #10; chk_res(32'd7,    "SUB 10-3");
                   a = 32'd3;       b = 32'd10;      #10; chk_res(32'hFFFFFFF9, "SUB 3-10=-7");
                   a = 32'd5;       b = 32'd5;       #10; chk_res(32'd0,    "SUB 5-5=0");

    // ===== SLL (左移，看 b 低5位) =====
    $display("--- SLL ---");
    op = ALU_SLL;  a = 32'h00000001; b = 32'd0;      #10; chk_res(32'h00000001, "SLL <<0");
                   a = 32'h00000001; b = 32'd4;      #10; chk_res(32'h00000010, "SLL <<4");
                   a = 32'h00000001; b = 32'd31;     #10; chk_res(32'h80000000, "SLL <<31");
                   a = 32'h00000001; b = 32'h104;    #10; chk_res(32'h00000010, "SLL ignore high bits");

    // ===== SRL (逻辑右移，高位补0) =====
    $display("--- SRL ---");
    op = ALU_SRL;  a = 32'h80000000; b = 32'd31;     #10; chk_res(32'h00000001, "SRL >>31");
                   a = 32'hF0000000; b = 32'd28;     #10; chk_res(32'h0000000F, "SRL >>28");

    // ===== SRA (算术右移，高位补符号位) =====
    $display("--- SRA ---");
    op = ALU_SRA;  a = 32'h80000000; b = 32'd31;     #10; chk_res(32'hFFFFFFFF, "SRA neg>>31");
                   a = 32'h80000000; b = 32'd4;      #10; chk_res(32'hF8000000, "SRA neg>>4");
                   a = 32'h40000000; b = 32'd4;      #10; chk_res(32'h04000000, "SRA pos>>4");

    // ===== SLT (有符号小于) =====
    $display("--- SLT (signed) ---");
    op = ALU_SLT;  a = 32'd3;        b = 32'd5;      #10; chk_res(32'd1, "SLT 3<5");
                   a = 32'd5;        b = 32'd3;      #10; chk_res(32'd0, "SLT 5<3");
                   a = 32'hFFFFFFFD; b = 32'd3;      #10; chk_res(32'd1, "SLT -3<3");
                   a = 32'd3;        b = 32'hFFFFFFFD; #10; chk_res(32'd0, "SLT 3<-3");

    // ===== SLTU (无符号小于) =====
    $display("--- SLTU (unsigned) ---");
    op = ALU_SLTU; a = 32'd3;        b = 32'd5;      #10; chk_res(32'd1, "SLTU 3<5");
                   a = 32'hFFFFFFFD; b = 32'd3;      #10; chk_res(32'd0, "SLTU big<3");

    // ===== XOR / OR / AND =====
    $display("--- Bitwise ---");
    op = ALU_XOR;  a = 32'hFF00FF00; b = 32'h0F0F0F0F; #10; chk_res(32'hF00FF00F, "XOR");
    op = ALU_OR;                                #10; chk_res(32'hFF0FFF0F, "OR");
    op = ALU_AND;                              #10; chk_res(32'h0F000F00, "AND");

    // ===== 分支判定 =====
    $display("--- Branch comparisons ---");
    op = ALU_EQ;   a = 32'd7;        b = 32'd7;      #10; chk_cmp(1'b1, "EQ 7==7");
                   a = 32'd7;        b = 32'd8;      #10; chk_cmp(1'b0, "EQ 7==8");
    op = ALU_NE;   a = 32'd7;        b = 32'd8;      #10; chk_cmp(1'b1, "NE 7!=8");
    op = ALU_LT;   a = 32'hFFFFFFFD; b = 32'd3;      #10; chk_cmp(1'b1, "LT -3<3");
                   a = 32'd3;        b = 32'hFFFFFFFD; #10; chk_cmp(1'b0, "LT 3<-3");
    op = ALU_GE;   a = 32'd3;        b = 32'hFFFFFFFD; #10; chk_cmp(1'b1, "GE 3>=-3");
    op = ALU_LTU;  a = 32'hFFFFFFFD; b = 32'd3;      #10; chk_cmp(1'b0, "LTU big<3");
    op = ALU_GEU;  a = 32'hFFFFFFFD; b = 32'd3;      #10; chk_cmp(1'b1, "GEU big>=3");

    // ===== 汇总 =====
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_alu
