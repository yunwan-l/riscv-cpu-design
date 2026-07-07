// =============================================================================
// tb_soc.sv — SoC 系统集成测试
// =============================================================================
// 测试内容：
//   1. 加载 SoC 测试程序到指令存储器
//   2. 提供时钟、复位、开关输入
//   3. 检查 GPIO 输出（LED）、Timer 计数、UART 发送状态
//
// 测试程序 (soc_test.S) 做了：
//   - 写 0x1234 到 GPIO OUTPUT
//   - 读 GPIO INPUT (开关值) → t2
//   - 启动 Timer
//   - 读 Timer COUNT → t5
//   - 发送 'H' 到 UART
//   - 把开关值写到 GPIO OUTPUT（覆盖之前的 0x1234）
// =============================================================================

`timescale 1ns/1ps

module tb_soc;

  logic        clk, rst_n;
  logic        uart_tx;
  logic [15:0] led;
  logic [15:0] sw;
  logic [31:0] pc_dbg;

  int errors = 0;
  int tests  = 0;

  rvp_soc dut (
    .clk_i    (clk),
    .rst_ni   (rst_n),
    .uart_tx_o(uart_tx),
    .led_o    (led),
    .sw_i     (sw),
    .pc_dbg_o (pc_dbg)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  // 检查任务
  task automatic chk(input cond, input [255:0] name);
    tests++;
    if (!cond) begin
      $display("  [FAIL] %0s", name);
      errors++;
    end else begin
      $display("  [ OK ] %0s", name);
    end
  endtask

  initial begin
    // 加载测试程序到指令存储器
    $readmemh("c:/Users/Lenovo/.trae-cn/work/6a4bbc0993ad5d12044988b4/soc_test_words.hex",
              dut.cpu.instr_mem.mem);

    // 设置开关输入
    sw = 16'hABCD;

    rst_n = 0;
    #20 rst_n = 1;

    $display("==========================================================");
    $display(" SoC Integration Test Start");
    $display("==========================================================");

    // 等待程序执行完成（18 条指令 + 流水线延迟）
    repeat (50) @(posedge clk);
    #1;

    // ===== 1. GPIO: LED 应该等于开关值 =====
    $display("--- GPIO ---");
    chk(led === 16'hABCD, "LED = switch value (0xABCD)");

    // ===== 2. GPIO: 第一次写入的 0x1234 应该被覆盖 =====
    // CPU 寄存器 t1 = x6 应该是 0x1234
    chk(dut.cpu.reg_file.regs[6] === 32'h1234, "t1 = 0x1234 (first GPIO write)");

    // ===== 3. GPIO: t2 = x7 应该是开关值 =====
    chk(dut.cpu.reg_file.regs[7] === 32'h0000ABCD, "t2 = switch input (0xABCD)");

    // ===== 4. Timer: 应该已启动且计数 > 0 =====
    $display("--- Timer ---");
    chk(dut.timer.enable === 1'b1, "Timer enabled");
    chk(dut.timer.count > 32'd0, "Timer count > 0");

    // t5 = x30 应该是读取到的计数值
    chk(dut.cpu.reg_file.regs[30] > 32'd0, "t5 = timer count > 0");

    // ===== 5. UART: 应该正在发送 'H' =====
    $display("--- UART ---");
    chk(dut.uart.tx_busy === 1'b1, "UART TX busy (sending 'H')");
    chk(dut.uart.tx_shift[7:0] === 8'h48, "UART shift reg = 'H'");

    // ===== 6. 总线地址译码验证 =====
    $display("--- Bus ---");
    // t0 = x5 = GPIO base address
    chk(dut.cpu.reg_file.regs[5] === 32'h10010000, "t0 = GPIO base (0x10010000)");
    // t3 = x28 = Timer base address
    chk(dut.cpu.reg_file.regs[28] === 32'h10020000, "t3 = Timer base (0x10020000)");
    // t6 = x31 = UART base address
    chk(dut.cpu.reg_file.regs[31] === 32'h10000000, "t6 = UART base (0x10000000)");

    // ===== 汇总 =====
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_soc
