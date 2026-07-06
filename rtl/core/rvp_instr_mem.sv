// =============================================================================
// rvp_instr_mem.sv — RVP 指令存储器
// =============================================================================
// 功能：根据 PC 地址读出 32 位指令。只读（单周期 CPU 不写指令存储器）。
//
// 接口：
//   addr_i  : PC 地址（字节地址）
//   instr_o : 读出的 32 位指令
//
// 设计要点：
//   1. 异步读：给地址立即出指令，单周期 CPU 一个周期内完成取指
//   2. 字对齐：RISC-V 指令 32 位=4字节，PC 低 2 位恒 0，用 addr[31:2] 做字索引
//   3. 初始化：用 $readmemh 从 .hex 文件加载程序，仿真时用
//   4. 容量：16K 条指令 = 64KB（够跑测试程序，FPGA 上可用 BRAM）
// =============================================================================

module rvp_instr_mem #(
  parameter int DEPTH = 16384  // 16K 条指令
) (
  input  logic [31:0] addr_i,
  output logic [31:0] instr_o
);

  // 存储阵列：DEPTH 个 32 位字
  logic [31:0] mem [0:DEPTH-1];

  // 异步读：用字节地址的高 30 位做字索引
  assign instr_o = mem[addr_i[31:2]];

  // 仿真初始化：从 hex 文件加载
  // 综合时这一段会被忽略（FPGA 上用 .coe/.mif 初始化 BRAM）
  initial begin
    // 默认填充 NOP（addi x0, x0, 0 = 0x00000013）
    for (int i = 0; i < DEPTH; i++) begin
      mem[i] = 32'h00000013;
    end
    // 如果有 hex 文件则加载（路径在 testbench 里用 plusarg 传入或写死）
    // $readmemh("program.hex", mem);
  end

endmodule : rvp_instr_mem
