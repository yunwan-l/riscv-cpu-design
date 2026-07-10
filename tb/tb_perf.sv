// =============================================================================
// tb_perf.sv — 性能计数器测试平台
// =============================================================================
// 功能：
//   1. 加载 3 个性能测试程序（矩阵乘法 / 冒泡排序 / 斐波那契）
//   2. 运行仿真并读取 CPU 内部 5 个性能计数器
//   3. 计算 CPI 并验证计算结果正确性
//   4. 输出格式化性能报告
//
// 停机检测：
//   程序结束时执行 `j end` 死循环，汇编器自动在控制流指令后插入 NOP。
//   因此 PC 在 end 和 end+4 之间交替，检测此模式即可判定程序结束。
//   检测条件：当前 PC == 2 周期前的 PC，且 != 1 周期前的 PC（交替模式）
//
// 性能计数器（CPU 内部寄存器，通过层次化引用读取）：
//   perf_cycle_r   : 总周期数
//   perf_inst_r    : 完成指令数
//   perf_stall_r   : Load-Use 停顿数
//   perf_flush_r   : 分支冲刷数
//   perf_branch_r  : 分支/跳转指令数
// =============================================================================

`timescale 1ns/1ps

module tb_perf;

  // -------------------------------------------------------------------------
  // 信号
  // -------------------------------------------------------------------------
  logic        clk;
  logic        rst_n;
  logic        uart_tx;
  logic [15:0] led;
  logic [15:0] sw;
  logic [31:0] pc_dbg;

  // -------------------------------------------------------------------------
  // DUT 实例化
  // -------------------------------------------------------------------------
  rvp_soc dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .uart_tx_o (uart_tx),
    .led_o     (led),
    .sw_i      (sw),
    .pc_dbg_o  (pc_dbg)
  );

  // -------------------------------------------------------------------------
  // 时钟生成：10ns 周期 = 100MHz（SoC 内部不分频，仿真直连）
  // -------------------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------------------
  // 停机检测：检测 j end 死循环的 PC 3周期重复模式
  // -------------------------------------------------------------------------
  // j end 自跳转时流水线 PC 序列：E → E+4 → E+8(flushed) → E → E+4 → E+8 → ...
  // 因为分支在 EX 阶段解决，IF 已取到 E+8 的错误指令（被 flush_if_id 冲刷）
  // 所以 PC 每 3 个周期重复一次
  logic [31:0] pc_q1, pc_q2, pc_q3;   // 1/2/3周期前的 PC
  logic        halt_flag;              // 停机标志

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q1     <= 32'hFFFFFFFF;
      pc_q2     <= 32'hFFFFFFFF;
      pc_q3     <= 32'hFFFFFFFF;
      halt_flag <= 1'b0;
    end else begin
      pc_q3 <= pc_q2;
      pc_q2 <= pc_q1;
      pc_q1 <= pc_dbg;
      // 3周期重复模式：当前PC == 3周期前PC
      if (pc_dbg == pc_q3 && pc_dbg != pc_q1 &&
          pc_q3 != 32'hFFFFFFFF && pc_dbg != 32'h0) begin
        halt_flag <= 1'b1;
      end
    end
  end

  // -------------------------------------------------------------------------
  // 性能结果存储
  // -------------------------------------------------------------------------
  integer cyc, ins, stl, fls, brh;
  real    cpi;
  integer pass_cnt;
  integer i;
  integer halt_cycle;   // 停机时的周期数

  // hex 文件路径（通过 plusarg 传入或使用默认值）
  string  hex_dir;
  string  hex_path;

  // -------------------------------------------------------------------------
  // 运行单个 benchmark 的任务
  // -------------------------------------------------------------------------
  task automatic run_bench(
    input string bench_name,
    input string hex_file,
    input integer max_cycles
  );
    integer cycle_count;
    begin
      // --- 复位 ---
      rst_n = 1'b0;
      sw    = 16'h0000;
      repeat (5) @(posedge clk);

      // --- 加载 hex 文件 ---
      hex_path = {hex_dir, "/", hex_file};
      $readmemh(hex_path, dut.cpu.icache.backing_mem.mem);

      // --- 清除数据 RAM（避免上一个 benchmark 残留数据干扰） ---
      for (i = 0; i < 2048; i = i + 1)
        dut.ram.mem[i] = 32'h0;

      // --- 释放复位 ---
      @(negedge clk);
      rst_n = 1'b1;

      // --- 运行程序，等待停机检测或超时 ---
      cycle_count = 0;
      // halt_flag 已被复位清零，等待程序结束
      while (!halt_flag && cycle_count < max_cycles) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
      end

      halt_cycle = cycle_count;

      // --- 超时检查 ---
      if (!halt_flag) begin
        $display("  [WARNING] 程序在 %0d 周期内未检测到停机", max_cycles);
      end

      // --- 读取性能计数器 ---
      cyc = dut.cpu.perf_cycle_r;
      ins = dut.cpu.perf_inst_r;
      stl = dut.cpu.perf_stall_r;
      fls = dut.cpu.perf_flush_r;
      brh = dut.cpu.perf_branch_r;

      // --- 计算 CPI ---
      if (ins > 0)
        cpi = real'(cyc) / real'(ins);
      else
        cpi = 0.0;

      // --- 打印结果 ---
      $display("============================================================");
      $display("  Benchmark: %s", bench_name);
      $display("============================================================");
      $display("  Halt Cycle       : %0d", halt_cycle);
      $display("  Total Cycles     : %0d", cyc);
      $display("  Instructions     : %0d", ins);
      $display("  Load-Use Stalls  : %0d", stl);
      $display("  Branch Flushes   : %0d", fls);
      $display("  Branch/Jump Instr: %0d", brh);
      $display("  CPI              : %.4f", cpi);
      $display("  Stall Rate       : %.2f%%", real'(stl)/real'(cyc)*100.0);
      $display("  Flush Rate       : %.2f%%", real'(fls)/real'(cyc)*100.0);
      $display("  Branch Rate      : %.2f%%", real'(brh)/real'(ins)*100.0);
      $display("------------------------------------------------------------");
    end
  endtask

  // -------------------------------------------------------------------------
  // 数据正确性验证
  // -------------------------------------------------------------------------

  // 验证矩阵乘法结果
  // C = A * B, A=[[1,2,3],[4,5,6],[7,8,9]], B=[[9,8,7],[6,5,4],[3,2,1]]
  // C=[[30,24,18],[84,69,54],[138,114,90]], 存于地址 0x80~0xA0
  task automatic check_matmul;
    integer w;  // word index (0x80/4 = 32)
    integer expected[9];
    integer errors;
    begin
      expected[0]=30;  expected[1]=24;  expected[2]=18;
      expected[3]=84;  expected[4]=69;  expected[5]=54;
      expected[6]=138; expected[7]=114; expected[8]=90;
      errors = 0;
      $display("  [Matmul] 数据验证:");
      for (w = 0; w < 9; w = w + 1) begin
        if (dut.ram.mem[32 + w] !== expected[w]) begin
          $display("    FAIL: C[%0d]=%0d, expected %0d",
                   w, dut.ram.mem[32+w], expected[w]);
          errors = errors + 1;
        end
      end
      if (errors == 0)
        $display("    PASS: 所有 9 个矩阵元素正确");
      else
        $display("    FAIL: %0d 个元素错误", errors);
      pass_cnt = pass_cnt + (errors == 0);
    end
  endtask

  // 验证冒泡排序结果
  // 输入 [5,2,8,1,9,3,7,4] → 排序后 [1,2,3,4,5,7,8,9]
  task automatic check_bubble;
    integer w;
    integer expected[8];
    integer errors;
    begin
      expected[0]=1; expected[1]=2; expected[2]=3; expected[3]=4;
      expected[4]=5; expected[5]=7; expected[6]=8; expected[7]=9;
      errors = 0;
      $display("  [Bubble] 数据验证:");
      for (w = 0; w < 8; w = w + 1) begin
        if (dut.ram.mem[w] !== expected[w]) begin
          $display("    FAIL: arr[%0d]=%0d, expected %0d",
                   w, dut.ram.mem[w], expected[w]);
          errors = errors + 1;
        end
      end
      if (errors == 0)
        $display("    PASS: 数组已正确排序");
      else
        $display("    FAIL: %0d 个元素错误", errors);
      pass_cnt = pass_cnt + (errors == 0);
    end
  endtask

  // 验证斐波那契结果
  // mem[0..9] = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
  task automatic check_fib;
    integer w;
    integer expected[10];
    integer errors;
    begin
      expected[0]=1;  expected[1]=1;  expected[2]=2;  expected[3]=3;
      expected[4]=5;  expected[5]=8;  expected[6]=13; expected[7]=21;
      expected[8]=34; expected[9]=55;
      errors = 0;
      $display("  [Fibonacci] 数据验证:");
      for (w = 0; w < 10; w = w + 1) begin
        if (dut.ram.mem[w] !== expected[w]) begin
          $display("    FAIL: fib[%0d]=%0d, expected %0d",
                   w, dut.ram.mem[w], expected[w]);
          errors = errors + 1;
        end
      end
      if (errors == 0)
        $display("    PASS: 10 个斐波那契数正确");
      else
        $display("    FAIL: %0d 个元素错误", errors);
      pass_cnt = pass_cnt + (errors == 0);
    end
  endtask

  // -------------------------------------------------------------------------
  // 主测试流程
  // -------------------------------------------------------------------------
  initial begin
    // --- 初始化 ---
    rst_n    = 1'b0;
    sw       = 16'h0000;
    pass_cnt = 0;

    // --- 获取 hex 文件目录 ---
    if (!$value$plusargs("HEX_DIR=%s", hex_dir))
      hex_dir = "../sw/tests";

    $display("");
    $display("############################################################");
    $display("#         RVP 流水线性能量化评估仿真                        #");
    $display("############################################################");
    $display("#  HEX 目录: %s", hex_dir);
    $display("#  时钟频率: 50 MHz (仿真计数，Fmax 来自 Vivado 报告)        #");
    $display("#  停机检测: PC 交替模式 (j end + nop)                       #");
    $display("############################################################");
    $display("");

    // ============================================================
    // Benchmark 1: 3x3 矩阵乘法（计算密集型）
    // ============================================================
    run_bench("3x3 Matrix Multiply (compute-intensive)",
              "perf_matmul.hex", 5000);
    check_matmul;
    $display("");

    // ============================================================
    // Benchmark 2: 冒泡排序（分支密集型）
    // ============================================================
    run_bench("Bubble Sort 8 elements (branch-intensive)",
              "perf_bubble.hex", 5000);
    check_bubble;
    $display("");

    // ============================================================
    // Benchmark 3: 斐波那契数列（控制流密集型）
    // ============================================================
    run_bench("Fibonacci 10 terms (control-flow-intensive)",
              "perf_fib.hex", 2000);
    check_fib;
    $display("");

    // ============================================================
    // 优化版 Benchmark（指令调度消除 Load-Use 停顿）
    // ============================================================
    $display("############################################################");
    $display("#       优化版基准测试（指令调度消除 Load-Use 停顿）         #");
    $display("############################################################");
    $display("");

    // ============================================================
    // Benchmark 4: 优化版矩阵乘法
    // ============================================================
    run_bench("3x3 Matrix Multiply OPTIMIZED (instruction scheduling)",
              "perf_matmul_opt.hex", 5000);
    check_matmul;
    $display("");

    // ============================================================
    // Benchmark 5: 优化版冒泡排序
    // ============================================================
    run_bench("Bubble Sort OPTIMIZED (instruction scheduling)",
              "perf_bubble_opt.hex", 5000);
    check_bubble;
    $display("");

    // ============================================================
    // Benchmark 6: 优化版斐波那契（无停顿，与原版相同）
    // ============================================================
    run_bench("Fibonacci OPTIMIZED (no stalls to eliminate)",
              "perf_fib_opt.hex", 2000);
    check_fib;
    $display("");

    // ============================================================
    // 汇总报告
    // ============================================================
    $display("############################################################");
    $display("#                       汇总报告                            #");
    $display("############################################################");
    $display("#  数据验证: %0d/6 通过 (3 原版 + 3 优化版)", pass_cnt);
    $display("#");
    $display("#  CPI 计算公式: CPI = Total Cycles / Instructions          #");
    $display("#  吞吐量公式:   MIPS = Fmax(MHz) / CPI                     #");
    $display("#  Fmax: 50 MHz (Vivado 综合后 SoC 核心域时钟)               #");
    $display("############################################################");
    $display("");

    // --- 结束 ---
    $finish;
  end

  // -------------------------------------------------------------------------
  // 超时保护
  // -------------------------------------------------------------------------
  initial begin
    #2000000;  // 2ms 超时（6 个 benchmark）
    $display("");
    $display("[TIMEOUT] 仿真超时，强制结束");
    $finish;
  end

endmodule : tb_perf
