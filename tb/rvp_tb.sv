/**
 * rvp_tb.sv - RVP SoC Testbench
 *
 * RVP处理器的SystemVerilog测试平台，用于仿真验证SoC功能。
 *
 * 参考: picorv32 testbench.v (421行)
 *
 * 功能:
 *   - 时钟生成 (可配置周期)
 *   - 复位序列生成
 *   - 通过$readmemh加载固件到指令存储器
 *   - 通过$value$plusargs支持命令行指定固件文件
 *   - 超时检测 (防止仿真挂起)
 *   - 测试结果检查
 *
 * 内存映射I/O (测试专用):
 *   0x1000_0000: UART THR - 写字符输出到控制台
 *   0x2000_0000: 测试完成标志 - 写123456789表示测试通过
 *   0x2000_0004: 测试返回码 (0=通过, 非0=失败码)
 *
 * 使用方法:
 *   仿真时通过+firmware参数指定固件:
 *   > vsim -voptargs="+firmware=test_program.hex" rvp_tb
 *   或:
 *   > verilator --binary -Gfirmware=\"test.hex\" rvp_tb.sv
 */

`timescale 1ns / 1ps

`include "rvp_config.svh"
`include "rvp_test_utils.svh"

module rvp_tb;

  // ==========================================================================
  // 参数
  // ==========================================================================

  // 时钟周期 (ns)
  localparam realtime CLK_PERIOD = 10;  // 10ns = 100MHz

  // 超时周期数 (防止仿真挂起)
  localparam integer TIMEOUT_CYCLES = 1_000_000;

  // GPIO宽度
  localparam int GPIO_WIDTH = `RVP_GPIO_WIDTH;

  // 固件文件路径 (可通过+firmware覆盖)
  string firmware = "firmware.hex";

  // ==========================================================================
  // 信号
  // ==========================================================================

  logic         clk;           // 系统时钟
  logic         rst_n;         // 系统复位 (低有效)

  // UART信号
  logic         uart_rx;       // UART接收
  logic         uart_tx;       // UART发送

  // GPIO信号
  logic [GPIO_WIDTH-1:0] gpio_in;
  logic [GPIO_WIDTH-1:0] gpio_out;

  // 测试控制
  logic         test_done;     // 测试完成标志
  logic [31:0]  test_result;   // 测试结果 (123456789=PASS)
  integer       cycle_count;   // 周期计数器

  // ==========================================================================
  // 时钟生成
  // ==========================================================================

  initial begin
    clk = 1'b0;
    forever begin
      #(CLK_PERIOD / 2) clk = ~clk;
    end
  end

  // ==========================================================================
  // 周期计数器
  // ==========================================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
    end
  end

  // ==========================================================================
  // 固件文件加载 (命令行参数解析)
  // ==========================================================================

  initial begin
    // 从命令行获取固件路径: +firmware="path/to/firmware.hex"
    if ($value$plusargs("firmware=%s", firmware)) begin
      $display("[%0t] Loading firmware: %s", $time, firmware);
    end else begin
      $display("[%0t] No firmware specified, using default: %s", $time, firmware);
    end
  end

  // ==========================================================================
  // SoC顶层实例化
  // ==========================================================================

  rvp_soc_top #(
    .SRAMInitFile (firmware)           // 传递固件文件给指令存储器
  ) dut (
    .clk_i        (clk),
    .rst_ni       (rst_n),

    // UART
    .uart_rx_i    (uart_rx),
    .uart_tx_o    (uart_tx),

    // GPIO
    .gpio_in_i    (gpio_in),
    .gpio_out_o   (gpio_out)
  );

  // ==========================================================================
  // UART回环 (可选: 自环测试)
  // ==========================================================================

  // 自环模式: TX直接连接到RX
  // assign uart_rx = uart_tx;

  // 正常模式: RX固定为高 (空闲)
  assign uart_rx = 1'b1;

  // ==========================================================================
  // GPIO输入驱动
  // ==========================================================================

  initial begin
    gpio_in = '0;
  end

  // ==========================================================================
  // 监控: 捕获CPU写入UART的数据并输出到控制台
  // ==========================================================================

  // 监控CPU对UART THR (0x1000_0000)的写入
  always @(posedge clk) begin
    if (rst_n && dut.host_req[0] && dut.host_we[0] &&
        (dut.host_addr[0][31:12] == 20'h10000)) begin
      // UART地址范围写入
      // TODO: 检查具体寄存器偏移，如果是THR则输出字符
      // $write("%c", dut.host_wdata[0][7:0]);
    end
  end

  // ==========================================================================
  // 监控: 测试结果检查
  // ==========================================================================

  // 监控CPU对测试标志地址 (0x2000_0000) 的写入
  // 写入123456789表示测试通过
  always @(posedge clk) begin
    if (rst_n && dut.host_req[0] && dut.host_we[0]) begin
      // TODO: 检查地址是否为0x2000_0000
      // if (dut.host_addr[0] == 32'h2000_0000) begin
      //   test_result <= dut.host_wdata[0];
      //   if (dut.host_wdata[0] == 32'h123456789) begin
      //     $display("\n========================================");
      //     $display("TEST PASSED");
      //     $display("Cycles: %0d", cycle_count);
      //     $display("========================================\n");
      //     test_done <= 1'b1;
      //   end else begin
      //     $display("\n========================================");
      //     $display("TEST FAILED: result=%0d", dut.host_wdata[0]);
      //     $display("========================================\n");
      //     test_done <= 1'b1;
      //   end
      // end
    end
  end

  // ==========================================================================
  // 超时检测
  // ==========================================================================

  always @(posedge clk) begin
    if (cycle_count > TIMEOUT_CYCLES && !test_done) begin
      $display("\n========================================");
      $display("TIMEOUT: Simulation exceeded %0d cycles", TIMEOUT_CYCLES);
      $display("========================================\n");
      $finish;
    end
  end

  // ==========================================================================
  // 复位序列
  // ==========================================================================

  initial begin
    // 初始化信号
    test_done   = 1'b0;
    test_result = 32'h0;
    cycle_count = 0;

    // 复位序列
    rst_n = 1'b0;
    #(CLK_PERIOD * 5);   // 保持复位5个周期
    rst_n = 1'b1;

    $display("[%0t] System reset released, starting test...", $time);
  end

  // ==========================================================================
  // 测试完成处理
  // ==========================================================================

  always @(posedge clk) begin
    if (test_done) begin
      #(CLK_PERIOD * 10);  // 等待10个周期
      $finish;
    end
  end

  // ==========================================================================
  // 波形转储 (仿真工具特定)
  // ==========================================================================

  initial begin
`ifdef VERILATOR
    // Verilator不需要波形设置
`elsif VCS
    $vcdpluson;
    $vcdpluson(0, dut);
`else
    // 默认: 生成VCD波形
    $dumpfile("rvp_tb.vcd");
    $dumpvars(0, dut);
`endif
  end

  // ==========================================================================
  // TODO: 可选扩展功能
  // ==========================================================================

  // TODO: 添加UART接收监控 (解析TX输出并打印字符)
  // TODO: 添加指令跟踪输出 (调试用)
  // TODO: 添加覆盖率收集
  // TODO: 添加自检测试向量生成
  // TODO: 添加与参考模型(如Spike)的协同仿真对比

endmodule
