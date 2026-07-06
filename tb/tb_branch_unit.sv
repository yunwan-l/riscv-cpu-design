// =============================================================================
// tb_branch_unit.sv — 分支判定单元测试
// =============================================================================
`timescale 1ns/1ps

module tb_branch_unit;

  logic is_branch, cmp_result, branch_taken;
  int errors = 0, tests = 0;

  rvp_branch_unit dut (
    .is_branch_i   (is_branch),
    .cmp_result_i  (cmp_result),
    .branch_taken_o(branch_taken)
  );

  task automatic chk(input logic exp, input [255:0] name);
    tests++;
    if (branch_taken !== exp) begin
      $display("  [FAIL] %0s : is_branch=%b cmp=%b => got %b exp %b",
               name, is_branch, cmp_result, branch_taken, exp);
      errors++;
    end else $display("  [ OK ] %0s", name);
  endtask

  initial begin
    $display("=== Branch Unit Test ===");
    is_branch = 0; cmp_result = 0; #10; chk(0, "non-branch, cmp=0");
    is_branch = 0; cmp_result = 1; #10; chk(0, "non-branch, cmp=1");
    is_branch = 1; cmp_result = 0; #10; chk(0, "branch, cmp=0 (not taken)");
    is_branch = 1; cmp_result = 1; #10; chk(1, "branch, cmp=1 (taken)");

    if (errors == 0) $display(" ALL PASSED (%0d tests)", tests);
    else             $display(" FAILED: %0d/%0d", errors, tests);
    $finish;
  end

endmodule
