// =============================================================================
// rvp_instr_mem.sv - RVP 指令存储器（双端口 BRAM，PMRU8 I-Cache 后备存储）
// =============================================================================
// 功能：作为 I-Cache 的后备存储器，存储程序指令。
//       双端口异步读（组合逻辑读），Port A 供指令取指，Port B 供预取。
//       FPGA 综合时通过 initial 块的 $readmemh 将固件烧入 BRAM。
//
// 接口：
//   clk_i    : 时钟（用于 Vivado BRAM 推断，异步读模式下不使用）
//   addr_a_i : Port A 字地址（PC[ADDR_BITS+1:2]，已右移2位）
//   instr_a_o: Port A 读出的 32 位指令
//   addr_b_i : Port B 字地址（预取地址）
//   instr_b_o: Port B 读出的 32 位指令
//
// 容量：DEPTH=2048 字 = 8KB
// =============================================================================

module rvp_instr_mem #(
  parameter int DEPTH = 2048,
  parameter int ADDR_BITS = $clog2(DEPTH)
) (
  input  logic                  clk_i,       // 时钟（BRAM推断用）
  input  logic [ADDR_BITS-1:0]  addr_a_i,    // Port A 地址
  output logic [31:0]           instr_a_o,   // Port A 数据输出
  input  logic [ADDR_BITS-1:0]  addr_b_i,    // Port B 地址
  output logic [31:0]           instr_b_o    // Port B 数据输出
);

  logic [31:0] mem [0:DEPTH-1];

  // 双端口异步读
  assign instr_a_o = mem[addr_a_i];
  assign instr_b_o = mem[addr_b_i];

  // FPGA 综合时通过 $readmemh 初始化 BRAM
  // 仿真时由 testbench 通过层次式引用加载测试程序
  // Vivado 综合器会执行此 initial 块，将固件数据嵌入比特流
  initial begin
    $readmemh("firmware.hex", mem);
  end

endmodule : rvp_instr_mem
