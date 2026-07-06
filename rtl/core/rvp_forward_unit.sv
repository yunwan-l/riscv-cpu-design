// =============================================================================
// rvp_forward_unit.sv — RVP 前递单元
// =============================================================================
// 功能：检测数据冒险，从 EX/MEM 或 MEM/WB 级"截获"数据，直接送给 EX 级的 ALU。
//
// 前递优先级（同时命中时，取最近的）：
//   EX/MEM 前递 > MEM/WB 前递
//   因为 EX/MEM 的数据比 MEM/WB 更"新"（更早的指令已经在 MEM/WB 了）
//
// 前递条件：
//   1. 源级（EX/MEM 或 MEM/WB）的 reg_write=1（会写回）
//   2. 源级的 rd != 0（x0 不可写，前递无意义）
//   3. 源级的 rd == 当前级的 rs1（或 rs2）
//
// 接口：
//   ex_rs1_addr_i / ex_rs2_addr_i : ID/EX 级的 rs1/rs2 地址（要读的寄存器）
//   mem_*  : EX/MEM 级信息
//   wb_*   : MEM/WB 级信息
//   forward_a_o / forward_b_o : 前递选择信号（00=寄存器堆, 01=MEM/WB, 10=EX/MEM）
// =============================================================================

module rvp_forward_unit (
  // ID/EX 级的源寄存器地址
  input  logic [4:0]  ex_rs1_addr_i,
  input  logic [4:0]  ex_rs2_addr_i,

  // EX/MEM 级信息
  input  logic [4:0]  mem_rd_addr_i,
  input  logic        mem_reg_write_i,

  // MEM/WB 级信息
  input  logic [4:0]  wb_rd_addr_i,
  input  logic        wb_reg_write_i,

  // 前递选择（2位：00=寄存器堆原始值, 01=MEM/WB前递, 10=EX/MEM前递）
  output logic [1:0]  forward_a_o,   // 控制 ALU 操作数 A
  output logic [1:0]  forward_b_o    // 控制 ALU 操作数 B
);

  // 默认：不前递，用寄存器堆的原始值
  logic [1:0] forward_a, forward_b;

  always_comb begin
    // =======================================================================
    // 操作数 A 前递（rs1）
    // =======================================================================
    // 优先级：EX/MEM > MEM/WB
    if (mem_reg_write_i && (mem_rd_addr_i != 5'd0) && (mem_rd_addr_i == ex_rs1_addr_i)) begin
      forward_a = 2'b10;   // 从 EX/MEM 前递
    end else if (wb_reg_write_i && (wb_rd_addr_i != 5'd0) && (wb_rd_addr_i == ex_rs1_addr_i)) begin
      forward_a = 2'b01;   // 从 MEM/WB 前递
    end else begin
      forward_a = 2'b00;   // 不前递
    end

    // =======================================================================
    // 操作数 B 前递（rs2）
    // =======================================================================
    if (mem_reg_write_i && (mem_rd_addr_i != 5'd0) && (mem_rd_addr_i == ex_rs2_addr_i)) begin
      forward_b = 2'b10;
    end else if (wb_reg_write_i && (wb_rd_addr_i != 5'd0) && (wb_rd_addr_i == ex_rs2_addr_i)) begin
      forward_b = 2'b01;
    end else begin
      forward_b = 2'b00;
    end
  end

  assign forward_a_o = forward_a;
  assign forward_b_o = forward_b;

endmodule : rvp_forward_unit
