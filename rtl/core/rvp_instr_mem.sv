// =============================================================================
// rvp_instr_mem.sv — RVP 指令存储器
// =============================================================================
// 功能：根据 PC 字地址读出 32 位指令。只读。
//
// 端口宽度说明：
//   addr_i 宽度 = ADDR_BITS（字地址，不含字节偏移位）
//   DEPTH=2048 → ADDR_BITS=11 → addr_i 为 11 位
//   端口每一位都被使用，避免综合 unconnected port warning
// =============================================================================

module rvp_instr_mem #(
  parameter int DEPTH = 2048,                    // 2K 条指令 = 8KB
  parameter int ADDR_BITS = $clog2(DEPTH)        // 字地址位宽（自动计算）
) (
  input  logic [ADDR_BITS-1:0] addr_i,           // 字地址（PC[ADDR_BITS+1:2]）
  output logic [31:0]           instr_o
);

  // 存储阵列：DEPTH 个 32 位字
  logic [31:0] mem [0:DEPTH-1];

  // 异步读
  assign instr_o = mem[addr_i];

  // 仿真时：testbench 用 $readmemh 覆盖 mem 加载测试程序
  // 综合时：RAM 不初始化（FPGA 上电后通过 JTAG/UART 加载程序）

endmodule : rvp_instr_mem
