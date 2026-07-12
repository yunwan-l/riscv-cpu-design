// =============================================================================
// tb_perf.sv - Performance Counter Testbench
// =============================================================================
// Functions:
//   1. Load 3 performance test programs (matmul / bubble / fibonacci)
//   2. Run simulation and read 5 internal performance counters
//   3. Compute CPI and verify computation results
//   4. Output formatted performance report
//
// Halt detection:
//   Program ends with `j end` infinite loop. Assembler inserts NOP after
//   control-flow instructions, so PC alternates between end and end+4.
//   Detection: current PC == PC 3 cycles ago, and != PC 1 cycle ago.
//
// Performance counters (CPU internal registers, read via hierarchical ref):
//   perf_cycle_r   : total cycle count
//   perf_inst_r    : completed instruction count
//   perf_stall_r   : load-use stall count
//   perf_flush_r   : branch flush count
//   perf_branch_r  : branch/jump instruction count
// =============================================================================

`timescale 1ns/1ps

module tb_perf;

  // -------------------------------------------------------------------------
  // Signals
  // -------------------------------------------------------------------------
  logic        clk;
  logic        rst_n;
  logic        uart_tx;
  logic [15:0] led;
  logic [15:0] sw;
  logic [31:0] pc_dbg;

  // -------------------------------------------------------------------------
  // DUT instance
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
  // Clock generation: 10ns period = 100MHz
  // -------------------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------------------
  // Halt detection: detect j end infinite loop (3-cycle PC repeat pattern)
  // -------------------------------------------------------------------------
  logic [31:0] pc_q1, pc_q2, pc_q3;
  logic        halt_flag;

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
      if (pc_dbg == pc_q3 && pc_dbg != pc_q1 &&
          pc_q3 != 32'hFFFFFFFF && pc_dbg != 32'h0) begin
        halt_flag <= 1'b1;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Performance result storage
  // -------------------------------------------------------------------------
  integer cyc, ins, stl, fls, brh;
  real    cpi;
  integer pass_cnt;
  integer i;
  integer halt_cycle;

  string  hex_dir;
  string  hex_path;

  // -------------------------------------------------------------------------
  // Run single benchmark task
  // -------------------------------------------------------------------------
  task automatic run_bench(
    input string bench_name,
    input string hex_file,
    input integer max_cycles
  );
    integer cycle_count;
    begin
      // --- Reset ---
      rst_n = 1'b0;
      sw    = 16'h0000;
      repeat (5) @(posedge clk);

      // --- Load hex file ---
      hex_path = {hex_dir, "/", hex_file};
      $readmemh(hex_path, dut.cpu.icache.bm.mem);

      // --- Clear data RAM (avoid leftover data from previous benchmark) ---
      for (i = 0; i < 2048; i = i + 1)
        dut.ram.mem[i] = 32'h0;

      // --- Release reset ---
      @(negedge clk);
      rst_n = 1'b1;

      // --- Run program, wait for halt or timeout ---
      cycle_count = 0;
      while (!halt_flag && cycle_count < max_cycles) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
      end

      halt_cycle = cycle_count;

      // --- Timeout check ---
      if (!halt_flag) begin
        $display("  [WARNING] No halt detected within %0d cycles", max_cycles);
      end

      // --- Read performance counters ---
      cyc = dut.cpu.perf_cycle_r;
      ins = dut.cpu.perf_inst_r;
      stl = dut.cpu.perf_stall_r;
      fls = dut.cpu.perf_flush_r;
      brh = dut.cpu.perf_branch_r;

      // --- Compute CPI ---
      if (ins > 0)
        cpi = real'(cyc) / real'(ins);
      else
        cpi = 0.0;

      // --- Print results ---
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
  // Data verification
  // -------------------------------------------------------------------------

  // Verify matrix multiply result
  // C = A * B, A=[[1,2,3],[4,5,6],[7,8,9]], B=[[9,8,7],[6,5,4],[3,2,1]]
  // C=[[30,24,18],[84,69,54],[138,114,90]], stored at addr 0x80~0xA0
  task automatic check_matmul;
    integer w;
    integer expected[9];
    integer errors;
    begin
      expected[0]=30;  expected[1]=24;  expected[2]=18;
      expected[3]=84;  expected[4]=69;  expected[5]=54;
      expected[6]=138; expected[7]=114; expected[8]=90;
      errors = 0;
      $display("  [Matmul] Data verification:");
      for (w = 0; w < 9; w = w + 1) begin
        if (dut.ram.mem[32 + w] !== expected[w]) begin
          $display("    FAIL: C[%0d]=%0d, expected %0d",
                   w, dut.ram.mem[32+w], expected[w]);
          errors = errors + 1;
        end
      end
      if (errors == 0)
        $display("    PASS: All 9 matrix elements correct");
      else
        $display("    FAIL: %0d elements wrong", errors);
      pass_cnt = pass_cnt + (errors == 0);
    end
  endtask

  // Verify bubble sort result
  // Input [5,2,8,1,9,3,7,4] -> sorted [1,2,3,4,5,7,8,9]
  task automatic check_bubble;
    integer w;
    integer expected[8];
    integer errors;
    begin
      expected[0]=1; expected[1]=2; expected[2]=3; expected[3]=4;
      expected[4]=5; expected[5]=7; expected[6]=8; expected[7]=9;
      errors = 0;
      $display("  [Bubble] Data verification:");
      for (w = 0; w < 8; w = w + 1) begin
        if (dut.ram.mem[w] !== expected[w]) begin
          $display("    FAIL: arr[%0d]=%0d, expected %0d",
                   w, dut.ram.mem[w], expected[w]);
          errors = errors + 1;
        end
      end
      if (errors == 0)
        $display("    PASS: Array correctly sorted");
      else
        $display("    FAIL: %0d elements wrong", errors);
      pass_cnt = pass_cnt + (errors == 0);
    end
  endtask

  // Verify fibonacci result
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
      $display("  [Fibonacci] Data verification:");
      for (w = 0; w < 10; w = w + 1) begin
        if (dut.ram.mem[w] !== expected[w]) begin
          $display("    FAIL: fib[%0d]=%0d, expected %0d",
                   w, dut.ram.mem[w], expected[w]);
          errors = errors + 1;
        end
      end
      if (errors == 0)
        $display("    PASS: All 10 Fibonacci numbers correct");
      else
        $display("    FAIL: %0d elements wrong", errors);
      pass_cnt = pass_cnt + (errors == 0);
    end
  endtask

  // -------------------------------------------------------------------------
  // Main test flow
  // -------------------------------------------------------------------------
  initial begin
    // --- Initialize ---
    rst_n    = 1'b0;
    sw       = 16'h0000;
    pass_cnt = 0;

    // --- Get hex directory from plusarg ---
    if (!$value$plusargs("HEX_DIR=%s", hex_dir))
      hex_dir = "../sw/tests";

    $display("");
    $display("############################################################");
    $display("#         RVP Pipeline Performance Benchmark               #");
    $display("############################################################");
    $display("#  HEX dir: %s", hex_dir);
    $display("#  Clock: 100 MHz (sim), Fmax from Vivado report            #");
    $display("#  Halt detect: PC alternating pattern (j end + nop)        #");
    $display("############################################################");
    $display("");

    // ============================================================
    // Benchmark 1: 3x3 Matrix Multiply (compute-intensive)
    // ============================================================
    run_bench("3x3 Matrix Multiply (compute-intensive)",
              "perf_matmul.hex", 5000);
    check_matmul;
    $display("");

    // ============================================================
    // Benchmark 2: Bubble Sort (branch-intensive)
    // ============================================================
    run_bench("Bubble Sort 8 elements (branch-intensive)",
              "perf_bubble.hex", 5000);
    check_bubble;
    $display("");

    // ============================================================
    // Benchmark 3: Fibonacci (control-flow-intensive)
    // ============================================================
    run_bench("Fibonacci 10 terms (control-flow-intensive)",
              "perf_fib.hex", 2000);
    check_fib;
    $display("");

    // ============================================================
    // Optimized benchmarks (instruction scheduling to eliminate Load-Use stalls)
    // ============================================================
    $display("############################################################");
    $display("#     Optimized benchmarks (eliminate Load-Use stalls)      #");
    $display("############################################################");
    $display("");

    // ============================================================
    // Benchmark 4: Optimized matrix multiply
    // ============================================================
    run_bench("3x3 Matrix Multiply OPTIMIZED (instruction scheduling)",
              "perf_matmul_opt.hex", 5000);
    check_matmul;
    $display("");

    // ============================================================
    // Benchmark 5: Optimized bubble sort
    // ============================================================
    run_bench("Bubble Sort OPTIMIZED (instruction scheduling)",
              "perf_bubble_opt.hex", 5000);
    check_bubble;
    $display("");

    // ============================================================
    // Benchmark 6: Optimized fibonacci (no stalls to eliminate)
    // ============================================================
    run_bench("Fibonacci OPTIMIZED (no stalls to eliminate)",
              "perf_fib_opt.hex", 2000);
    check_fib;
    $display("");

    // ============================================================
    // Summary report
    // ============================================================
    $display("############################################################");
    $display("#                      Summary Report                       #");
    $display("############################################################");
    $display("#  Data verification: %0d/6 passed (3 original + 3 optimized)", pass_cnt);
    $display("#");
    $display("#  CPI formula:  CPI = Total Cycles / Instructions           #");
    $display("#  MIPS formula: MIPS = Fmax(MHz) / CPI                     #");
    $display("#  Fmax: 12.5 MHz (Vivado post-implementation SoC clock)     #");
    $display("############################################################");
    $display("");

    // --- End ---
    $finish;
  end

  // -------------------------------------------------------------------------
  // Timeout protection
  // -------------------------------------------------------------------------
  initial begin
    #2000000;  // 2ms timeout (6 benchmarks)
    $display("");
    $display("[TIMEOUT] Simulation timed out, forcing end");
    $finish;
  end

endmodule : tb_perf
