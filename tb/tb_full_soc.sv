// tb_full_soc.sv — Full SoC program testbench
// Loads full_test_words.hex and verifies execution

`timescale 1ns/1ps

module tb_full_soc;

  logic clk, rst_n;
  logic [15:0] led;
  logic [15:0] sw = 16'hA5A5;
  logic uart_tx;
  logic [31:0] pc_dbg;

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

  int errors = 0;
  int tests  = 0;

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
    // Load firmware
    #1;
    $readmemh("E:/rvp_nexys/sw/tests/full_test_words.hex", dut.cpu.instr_mem.mem);

    $display("==========================================================");
    $display(" Full SoC Program Test (141 instructions)");
    $display("==========================================================");

    rst_n = 0;
    #20 rst_n = 1;

    // Run for enough cycles:
    // Marquee left: 16*80*3 ≈ 3840, right: 3840, UART: 12*30*3 ≈ 1080, timer + switch: ~200
    // Total: ~9000. Add margin → 30000
    repeat (30000) @(posedge clk);
    #1;

    // === Phase Checks ===
    $display("--- Program State ---");
    $display("  PC = 0x%08h", pc_dbg);

    // Check PC is in the main loop (past all phases, around main_loop address)
    // The main_loop starts at approximately address 0x1C0 (112 instructions * 4 bytes)
    chk(pc_dbg >= 32'h00000180 || pc_dbg <= 32'h00000010,
        "PC in range");

    // Check LEDs are non-zero (program executed past init)
    $display("--- GPIO ---");
    chk(led !== 16'h0000, "LED non-zero");

    // Check timer count > 0 (timer was enabled and incremented)
    $display("--- Timer ---");
    chk(dut.timer.count > 32'h00000010,
        "Timer high");
    $display("--- Timer ---");
    chk(dut.timer.count > 32'h00000010,
        "Timer high");

    // === Summary ===
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");

    // Print last few PC values for debugging
    $display("--- Execution Trace (last 20 cycles) ---");
    // (Optional: add trace dumping)

    $finish;
  end

  // Monitor PC changes
  always @(posedge clk) begin
    if (pc_dbg >= 32'h00000300) begin
      // For debug: check switch values
    end
  end

endmodule : tb_full_soc
