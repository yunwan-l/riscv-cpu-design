// =============================================================================
// tb_rv32ui_p_all.sv — RV32I 全指令自检测试
// =============================================================================
// 加载 rv32ui_p_all.hex 到指令存储器，运行后检查 gp(x3)：
//   gp=1 → 全部通过
//   gp=其他 → 第 N 个测试失败
//
// 运行方式（在 tb/ 目录下）：
//   vlib work
//   vlog -sv ../rtl/rvp_pkg.sv ../rtl/core/rvp_alu.sv ... tb_rv32ui_p_all.sv
//   vsim -c -do "run -all; quit" tb_rv32ui_p_all
// =============================================================================

`timescale 1ns/1ps

module tb_rv32ui_p_all;

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

  // 外部数据存储器
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

  // 死循环检测：如果 PC 连续多次不变，说明进入了 pass/fail 死循环
  logic [31:0] last_pc;
  int same_pc_count;
  bit done;

  initial begin
    // 加载测试程序
    $readmemh("c:/Users/Lenovo/.trae-cn/work/6a4bbc0993ad5d12044988b4/rv32ui_p_all_words.hex",
              dut.instr_mem.mem);

    rst_n = 0;
    last_pc = 32'h0;
    same_pc_count = 0;
    done = 0;

    #20 rst_n = 1;

    $display("==========================================================");
    $display(" RV32I Self-Check Test Start (242 instructions)");
    $display("==========================================================");

    // 最多运行 600 个周期，或检测到死循环
    for (int i = 0; i < 600 && !done; i++) begin
      @(posedge clk);
      #1;
      // 死循环检测
      if (pc === last_pc) begin
        same_pc_count++;
        if (same_pc_count >= 5) done = 1;
      end else begin
        same_pc_count = 0;
        last_pc = pc;
      end
    end

    $display("");
    $display("==========================================================");
    if (dut.reg_file.regs[3] == 32'd1) begin
      $display(" RESULT: ALL PASSED  (gp = 1)");
    end else begin
      $display(" RESULT: FAILED at test #%0d  (gp = %0d)", dut.reg_file.regs[3], dut.reg_file.regs[3]);
    end
    $display(" Final PC = %h", pc);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_rv32ui_p_all
