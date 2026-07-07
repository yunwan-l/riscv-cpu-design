// =============================================================================
// tb_register_file.sv — 寄存器堆单元测试
// =============================================================================
// 用法（ModelSim 命令行，在 tb/ 目录下）：
//   vlib work
//   vlog -sv ../rtl/rvp_pkg.sv ../rtl/core/rvp_register_file.sv tb_register_file.sv
//   vsim -c -do "run -all; quit" tb_register_file
//
// 测试内容：
//   1. 复位后所有寄存器为 0
//   2. 写入后下一周期可读出正确值
//   3. x0 永远读 0（即使写它）
//   4. 两端口同时读不同寄存器
//   5. 同周期写读同地址 → 读到旧值（写沿才生效）
// =============================================================================

`timescale 1ns/1ps

module tb_register_file;

  logic        clk, rst_n;
  logic        we;
  logic [4:0]  waddr, raddr1, raddr2;
  logic [31:0] wdata, rdata1, rdata2;

  int errors = 0;
  int tests  = 0;

  // --- 例化 DUT ---
  rvp_register_file dut (
    .clk_i    (clk),
    .rst_ni   (rst_n),
    .we_i     (we),
    .waddr_i  (waddr),
    .wdata_i  (wdata),
    .raddr1_i (raddr1),
    .rdata1_o (rdata1),
    .raddr2_i (raddr2),
    .rdata2_o (rdata2)
  );

  // --- 时钟：10ns 周期 ---
  initial clk = 0;
  always #5 clk = ~clk;

  // --- 检查任务 ---
  task automatic chk(input [31:0] got, input [31:0] exp, input [255:0] name);
    tests++;
    if (got !== exp) begin
      $display("  [FAIL] %0s : got %h, exp %h", name, got, exp);
      errors++;
    end else begin
      $display("  [ OK ] %0s : %h", name, got);
    end
  endtask

  // --- 写任务：在时钟沿写入 ---
  task automatic wr(input [4:0] addr, input [31:0] data);
    begin
      @(negedge clk);       // 在下降沿驱动，避免冒险
      we    = 1;
      waddr = addr;
      wdata = data;
      @(negedge clk);
      we    = 0;
    end
  endtask

  initial begin
    // 初始化
    we = 0; waddr = 0; wdata = 0; raddr1 = 0; raddr2 = 0;
    rst_n = 0;
    #20 rst_n = 1;   // 释放复位
    @(negedge clk);

    $display("==========================================================");
    $display(" Register File Testbench Start");
    $display("==========================================================");

    // ===== 1. 复位后读所有关键寄存器应为 0 =====
    $display("--- After reset, all regs should be 0 ---");
    raddr1 = 5'd1;  #1; chk(rdata1, 32'h0, "x1 after reset");
    raddr1 = 5'd5;  #1; chk(rdata1, 32'h0, "x5 after reset");
    raddr1 = 5'd31; #1; chk(rdata1, 32'h0, "x31 after reset");

    // ===== 2. 写入后读出 =====
    $display("--- Write & read back ---");
    wr(5'd3, 32'hDEADBEEF);
    raddr1 = 5'd3; #1; chk(rdata1, 32'hDEADBEEF, "x3 = DEADBEEF");

    wr(5'd10, 32'h12345678);
    raddr1 = 5'd10; #1; chk(rdata1, 32'h12345678, "x10 = 12345678");

    wr(5'd31, 32'hFFFFFFFF);
    raddr1 = 5'd31; #1; chk(rdata1, 32'hFFFFFFFF, "x31 = FFFFFFFF");

    // ===== 3. x0 永远为 0 =====
    $display("--- x0 must always be 0 ---");
    wr(5'd0, 32'hCAFEBABE);   // 试图写 x0
    raddr1 = 5'd0; #1; chk(rdata1, 32'h0, "x0 stays 0 after write");

    // ===== 4. 两端口同时读不同寄存器 =====
    $display("--- Dual port read ---");
    wr(5'd7, 32'hAAAA0000);
    wr(5'd8, 32'h0000BBBB);
    raddr1 = 5'd7; raddr2 = 5'd8; #1;
    chk(rdata1, 32'hAAAA0000, "port1 reads x7");
    chk(rdata2, 32'h0000BBBB, "port2 reads x8");

    // ===== 5. 同周期写读同地址 → 读到旧值（写沿才生效）=====
    $display("--- Write & read same addr same cycle (read old value) ---");
    wr(5'd15, 32'h11111111);      // 先写入 x15 = 11111111
    // 本周期写 x15=22222222，同时读 x15
    // 无写优先：读到的是旧值（11111111），新值下个周期才生效
    @(negedge clk);
    raddr1 = 5'd15;
    we     = 1;
    waddr  = 5'd15;
    wdata  = 32'h22222222;
    #1;
    chk(rdata1, 32'h11111111, "read old value during write cycle");  // 读到旧值
    @(negedge clk);
    we = 0;
    #1;
    chk(rdata1, 32'h22222222, "read new value after write");        // 现在才是新值

    // ===== 汇总 =====
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_register_file
