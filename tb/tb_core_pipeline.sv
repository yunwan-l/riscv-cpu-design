// =============================================================================
// tb_core_pipeline.sv — 流水线 CPU 集成测试
// =============================================================================
// 测试覆盖：数据冒险(前递)、Load-Use冒险(停顿)、控制冒险(分支/跳转冲刷)
// 注意：CPU 的数据存储器已移到外部（SoC 总线接口），这里单独例化。
// =============================================================================

`timescale 1ns/1ps

module tb_core_pipeline;

  import rvp_pkg::*;

  logic clk, rst_n;
  logic [31:0] pc, instr;
  logic        illegal;

  // 数据总线信号
  logic [31:0]    dbus_addr;
  logic           dbus_read, dbus_write;
  mem_size_e      dbus_size;
  logic           dbus_unsigned;
  logic [31:0]    dbus_wdata;
  logic [31:0]    dbus_rdata;

  int errors = 0;
  int tests  = 0;

  rvp_core_pipeline dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .pc_o           (pc),
    .instr_o        (instr),
    .illegal_o      (illegal),
    .dbus_addr_o    (dbus_addr),
    .dbus_read_o    (dbus_read),
    .dbus_write_o   (dbus_write),
    .dbus_size_o    (dbus_size),
    .dbus_unsigned_o(dbus_unsigned),
    .dbus_wdata_o   (dbus_wdata),
    .dbus_rdata_i   (dbus_rdata)
  );

  // 外部数据存储器（SoC 顶层会放总线互连，这里直接连）
  rvp_data_mem data_mem (
    .clk_i         (clk),
    .addr_i        (dbus_addr),
    .write_data_i  (dbus_wdata),
    .mem_read_i    (dbus_read),
    .mem_write_i   (dbus_write),
    .mem_size_i    (dbus_size),
    .mem_unsigned_i(dbus_unsigned),
    .read_data_o   (dbus_rdata)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic chk_reg(input [4:0] r, input [31:0] exp, input [255:0] name);
    tests++;
    if (dut.reg_file.regs[r] !== exp) begin
      $display("  [FAIL] %-28s : x%0d = %0d, exp %0d", name, r, dut.reg_file.regs[r], exp);
      errors++;
    end else begin
      $display("  [ OK ] %-28s : x%0d = %0d", name, r, dut.reg_file.regs[r]);
    end
  endtask

  task automatic chk_mem(input [31:0] addr, input [31:0] exp, input [255:0] name);
    tests++;
    if (data_mem.mem[addr[31:2]] !== exp) begin
      $display("  [FAIL] %-28s : MEM[%0d]=%0d, exp %0d", name, addr, data_mem.mem[addr[31:2]], exp);
      errors++;
    end else begin
      $display("  [ OK ] %-28s : MEM[%0d]=%0d", name, addr, data_mem.mem[addr[31:2]]);
    end
  endtask

  initial begin
    // 加载测试程序
    $readmemh("c:/Users/Lenovo/.trae-cn/work/6a4bbc0993ad5d12044988b4/pipeline_test_words.hex",
              dut.instr_mem.mem);

    rst_n = 0;
    #20 rst_n = 1;

    $display("==========================================================");
    $display(" Pipeline CPU Integration Test Start");
    $display("==========================================================");

    // 24 条指令 + 流水线延迟 + 冲刷惩罚，给足够周期
    repeat (40) @(posedge clk);
    #1;

    // ===== 1. 数据冒险：EX→EX 前递 =====
    $display("--- Data hazard (EX->EX forward) ---");
    chk_reg(1,  32'd5,  "x1 = 5 (addi)");
    chk_reg(2,  32'd8,  "x2 = 8 (forward x1)");
    chk_reg(3,  32'd13, "x3 = 13 (forward x1,x2)");

    // ===== 2. 数据冒险：MEM→EX 前递 =====
    $display("--- Data hazard (MEM->WB forward) ---");
    chk_reg(4,  32'd10, "x4 = 10");
    chk_reg(5,  32'd11, "x5 = 11 (forward x4)");
    chk_reg(6,  32'd0,  "x6 = 0");
    chk_reg(7,  32'd21, "x7 = 21");

    // ===== 3. Load-Use 冒险（停顿）=====
    $display("--- Load-Use hazard (stall) ---");
    chk_reg(8,  32'd42, "x8 = 42");
    chk_reg(9,  32'd42, "x9 = 42 (lw)");
    chk_reg(10, 32'd47, "x10 = 47 (load-use)");

    // ===== 4. 控制冒险：分支跳转 =====
    $display("--- Control hazard (branch taken) ---");
    chk_reg(11, 32'd7,  "x11 = 7");
    chk_reg(12, 32'd7,  "x12 = 7");
    chk_reg(13, 32'd55, "x13 = 55 (branch taken)");

    // ===== 5. 不跳转的分支 =====
    $display("--- Control hazard (branch not taken) ---");
    chk_reg(14, 32'd1,  "x14 = 1");
    chk_reg(15, 32'd2,  "x15 = 2");
    chk_reg(16, 32'd66, "x16 = 66 (bne taken)");

    // ===== 6. JAL 跳转 =====
    $display("--- Control hazard (JAL) ---");
    chk_reg(17, 32'd88, "x17 = ret addr");
    chk_reg(18, 32'd44, "x18 = 44 (jal skip)");

    // ===== 内存检查 =====
    $display("--- Memory ---");
    chk_mem(32'h0, 32'd42, "MEM[0] = 42");

    // ===== 汇总 =====
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_core_pipeline
