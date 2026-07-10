// =============================================================================
// rvp_instr_mem.sv - RVP 指令存储器（Backing Store for I-Cache）
// =============================================================================
// 功能：作为 I-Cache 的后备存储器，存储程序指令。
//       异步读（组合逻辑读），同步写（时钟沿写）。
//       FPGA 综合时通过 initial 块的 $readmemh 将固件烧入 BRAM。
//
// 接口：
//   addr_i : 字地址（PC[ADDR_BITS+1:2]，已右移2位）
//   instr_o: 读出的 32 位指令
//
// 容量：DEPTH=2048 字 = 8KB
// =============================================================================

module rvp_instr_mem #(
  parameter int DEPTH = 2048,
  parameter int ADDR_BITS = $clog2(DEPTH)
) (
  input  logic [ADDR_BITS-1:0] addr_i,
  output logic [31:0]          instr_o
);

  logic [31:0] mem [0:DEPTH-1];

  // 异步读
  assign instr_o = mem[addr_i];

  // FPGA 综合时通过 $readmemh 初始化 BRAM
  // 仿真时由 testbench 通过层次化引用加载测试程序
  // Vivado 综合器会执行此 initial 块，将固件数据嵌入比特流
  // 使用 include_dirs 中的路径搜索 firmware.hex
  initial begin
    $readmemh("firmware.hex", mem);
  end

endmodule : rvp_instr_mem
