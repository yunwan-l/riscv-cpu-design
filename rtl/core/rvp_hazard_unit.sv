// =============================================================================
// rvp_hazard_unit.sv — RVP 冒险检测单元
// =============================================================================
// 功能：检测 Load-Use 冒险，需要时停顿流水线一拍。
//
// Load-Use 冒险场景：
//   I1: lw  x3, 0(x1)    ← 数据在 MEM 级才出来
//   I2: add x4, x3, x5   ← 但 I2 在 EX 级就需要 x3，来不及前递！
//
// 解决：停顿一拍。I2 在 ID 级等一拍，等 I1 到 MEM/WB 后再前递。
//
// 停顿操作：
//   - PC 保持不变（IF 级不取新指令）
//   - IF/ID 寄存器保持不变（ID 级保持当前指令）
//   - ID/EX 寄存器写入 NOP（EX 级插入气泡）
//
// 接口：
//   id_ex_mem_read_i : ID/EX 级的指令是否是 load
//   id_ex_rd_addr_i  : ID/EX 级的 rd 地址（load 的目标寄存器）
//   if_id_rs1/rs2    : IF/ID 级的 rs1/rs2（下一条指令要用的寄存器）
//   stall_o          : 1=需要停顿
// =============================================================================

module rvp_hazard_unit (
  input  logic        id_ex_mem_read_i,   // 前一条指令（EX级）是否是 load
  input  logic [4:0]  id_ex_rd_addr_i,    // 前一条指令的 rd
  input  logic [4:0]  if_id_rs1_addr_i,   // 当前指令（ID级）的 rs1
  input  logic [4:0]  if_id_rs2_addr_i,   // 当前指令（ID级）的 rs2
  output logic        stall_o             // 1=停顿一拍
);

  // Load-Use 冒险检测：
  // 前一条是 load AND 其 rd == 当前指令的 rs1 或 rs2
  // 且 rd != 0（x0 不可能产生冒险）
  logic load_use_hazard;

  always_comb begin
    load_use_hazard = id_ex_mem_read_i &&
                      (id_ex_rd_addr_i != 5'd0) &&
                      ((id_ex_rd_addr_i == if_id_rs1_addr_i) ||
                       (id_ex_rd_addr_i == if_id_rs2_addr_i));
    stall_o = load_use_hazard;
  end

endmodule : rvp_hazard_unit
