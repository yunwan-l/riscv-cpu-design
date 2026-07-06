// =============================================================================
// tb_core_single.sv — 单周期 CPU 集成测试
// =============================================================================
// 用法（ModelSim，在 tb/ 目录下）：
//   vlib work
//   vlog -sv ../rtl/rvp_pkg.sv ../rtl/core/rvp_alu.sv ../rtl/core/rvp_register_file.sv \
//          ../rtl/core/rvp_imm_generator.sv ../rtl/core/rvp_decoder.sv \
//          ../rtl/core/rvp_branch_unit.sv ../rtl/core/rvp_instr_mem.sv \
//          ../rtl/core/rvp_data_mem.sv ../rtl/core/rvp_core_single.sv tb_core_single.sv
//   vsim -c -do "run -all; quit" tb_core_single
//
// 测试策略：
//   1. 用 $readmemh 把测试程序加载到指令存储器
//   2. 复位后运行 20 个周期（足够跑完 14 条指令）
//   3. 通过层次化引用检查寄存器堆和数据存储器的值
// =============================================================================

`timescale 1ns/1ps

module tb_core_single;

  logic clk, rst_n;
  logic [31:0] pc, instr;
  logic        illegal;

  int errors = 0;
  int tests  = 0;

  rvp_core_single dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .pc_o      (pc),
    .instr_o   (instr),
    .illegal_o (illegal)
  );

  // 时钟
  initial clk = 0;
  always #5 clk = ~clk;

  // 检查寄存器值
  task automatic chk_reg(input [4:0] r, input [31:0] exp, input [255:0] name);
    tests++;
    if (dut.reg_file.regs[r] !== exp) begin
      $display("  [FAIL] %0s : x%0d = %h, exp %h", name, r, dut.reg_file.regs[r], exp);
      errors++;
    end else begin
      $display("  [ OK ] %0s : x%0d = %h", name, r, dut.reg_file.regs[r]);
    end
  endtask

  // 检查内存值
  task automatic chk_mem(input [31:0] addr, input [31:0] exp, input [255:0] name);
    tests++;
    if (dut.data_mem.mem[addr[31:2]] !== exp) begin
      $display("  [FAIL] %0s : MEM[%0d] = %h, exp %h", name, addr, dut.data_mem.mem[addr[31:2]], exp);
      errors++;
    end else begin
      $display("  [ OK ] %0s : MEM[%0d] = %h", name, addr, dut.data_mem.mem[addr[31:2]]);
    end
  endtask

  initial begin
    // 加载测试程序到指令存储器
    $readmemh("c:/Users/Lenovo/.trae-cn/work/6a4bbc0993ad5d12044988b4/core_test_words.hex",
              dut.instr_mem.mem);

    // 复位
    rst_n = 0;
    #20 rst_n = 1;

    $display("==========================================================");
    $display(" Single-Cycle CPU Integration Test Start");
    $display("==========================================================");

    // 运行 20 个周期（14 条指令 + 余量）
    repeat (20) @(posedge clk);
    #1;  // 等待信号稳定

    // ===== 检查寄存器值 =====
    $display("--- Register values ---");
    chk_reg(1,  32'd5,  "x1 = 5 (addi)");
    chk_reg(2,  32'd3,  "x2 = 3 (addi)");
    chk_reg(3,  32'd8,  "x3 = 8 (add)");
    chk_reg(4,  32'd2,  "x4 = 2 (sub)");
    chk_reg(5,  32'd1,  "x5 = 1 (and)");
    chk_reg(6,  32'd7,  "x6 = 7 (or)");
    chk_reg(7,  32'd8,  "x7 = 8 (lw)");
    chk_reg(8,  32'd42, "x8 = 42 (branch taken)");
    chk_reg(9,  32'd20, "x9 = 20 (slli)");
    chk_reg(10, 32'd1,  "x10 = 1 (slt)");

    // ===== 检查内存值 =====
    $display("--- Memory values ---");
    chk_mem(32'h0, 32'd8, "MEM[0] = 8 (sw)");

    // ===== 汇总 =====
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_core_single
