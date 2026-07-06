// =============================================================================
// rvp_pipeline_regs.sv — RVP 流水线寄存器
// =============================================================================
// 4 组流水线寄存器：IF/ID, ID/EX, EX/MEM, MEM/WB
// 每组在时钟上升沿把上一级的结果锁存，供下一级使用。
//
// 关键控制信号：
//   flush_i : 冲刷（写 NOP），用于分支/跳转时清掉错误进入的指令
//   stall_i : 停顿（保持不更新），用于 Load-Use 冒险
//
// 设计要点：
//   - 冲刷优先级高于停顿：flush=1 时无论 stall 如何，都写 NOP
//   - 每级寄存器可独立冲刷/停顿（由流水线核心分别控制）
//   - NOP = 控制信号全零的指令（reg_write=0, mem_write=0, branch=0...）
// =============================================================================

module rvp_pipeline_regs (
  input  logic clk_i,
  input  logic rst_ni,

  // ===========================================================================
  // IF/ID 寄存器：锁存 PC 和指令
  // ===========================================================================
  input  logic        if_id_flush_i,
  input  logic        if_id_stall_i,
  input  logic [31:0] if_pc_i,
  input  logic [31:0] if_instr_i,
  output logic [31:0] id_pc_o,
  output logic [31:0] id_instr_o,

  // ===========================================================================
  // ID/EX 寄存器：锁存译码结果 + 读出的寄存器值 + 立即数 + PC
  // ===========================================================================
  input  logic              id_ex_flush_i,
  input  logic              id_ex_stall_i,
  input  logic [31:0]       id_pc_i,
  input  rvp_pkg::ctrl_t    id_ctrl_i,
  input  logic [31:0]       id_rs1_data_i,
  input  logic [31:0]       id_rs2_data_i,
  input  logic [31:0]       id_imm_i,
  output logic [31:0]       ex_pc_o,
  output rvp_pkg::ctrl_t    ex_ctrl_o,
  output logic [31:0]       ex_rs1_data_o,
  output logic [31:0]       ex_rs2_data_o,
  output logic [31:0]       ex_imm_o,

  // ===========================================================================
  // EX/MEM 寄存器：锁存 ALU 结果 + 写数据 + 控制信号
  // ===========================================================================
  input  logic              ex_mem_flush_i,   // 通常不用，保留接口
  input  logic              ex_mem_stall_i,   // 通常不用，保留接口
  input  logic [31:0]       ex_pc_i,
  input  rvp_pkg::ctrl_t    ex_ctrl_i,
  input  logic [31:0]       ex_alu_result_i,
  input  logic [31:0]       ex_rs2_data_i,    // store 的写数据
  input  logic [31:0]       ex_imm_i,         // lui 写回需要
  output logic [31:0]       mem_pc_o,
  output rvp_pkg::ctrl_t    mem_ctrl_o,
  output logic [31:0]       mem_alu_result_o,
  output logic [31:0]       mem_rs2_data_o,
  output logic [31:0]       mem_imm_o,

  // ===========================================================================
  // MEM/WB 寄存器：锁存 ALU 结果 + 内存读数据 + 控制信号 + 立即数
  // ===========================================================================
  input  logic              mem_wb_flush_i,
  input  logic              mem_wb_stall_i,
  input  logic [31:0]       mem_pc_i,
  input  rvp_pkg::ctrl_t    mem_ctrl_i,
  input  logic [31:0]       mem_alu_result_i,
  input  logic [31:0]       mem_rdata_i,
  output logic [31:0]       wb_pc_o,
  output rvp_pkg::ctrl_t    wb_ctrl_o,
  output logic [31:0]       wb_alu_result_o,
  output logic [31:0]       wb_rdata_o
);

  import rvp_pkg::*;

  // NOP 控制信号（全零，不写回不访存不分支）
  function automatic ctrl_t ctrl_nop();
    ctrl_t c = ctrl_zero();
    c.illegal = 1'b0;  // NOP 不是非法指令
    return c;
  endfunction

  // ===========================================================================
  // IF/ID 寄存器
  // ===========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      id_pc_o    <= 32'b0;
      id_instr_o <= 32'h00000013;  // NOP
    end else if (if_id_flush_i) begin
      // 冲刷：写入 NOP
      id_pc_o    <= 32'b0;
      id_instr_o <= 32'h00000013;
    end else if (!if_id_stall_i) begin
      // 正常更新（stall=0 时才更新）
      id_pc_o    <= if_pc_i;
      id_instr_o <= if_instr_i;
    end
    // stall=1 且 flush=0：保持不变
  end

  // ===========================================================================
  // ID/EX 寄存器
  // ===========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ex_pc_o      <= 32'b0;
      ex_ctrl_o    <= ctrl_nop();
      ex_rs1_data_o<= 32'b0;
      ex_rs2_data_o<= 32'b0;
      ex_imm_o     <= 32'b0;
    end else if (id_ex_flush_i) begin
      ex_pc_o      <= 32'b0;
      ex_ctrl_o    <= ctrl_nop();
      ex_rs1_data_o<= 32'b0;
      ex_rs2_data_o<= 32'b0;
      ex_imm_o     <= 32'b0;
    end else if (!id_ex_stall_i) begin
      ex_pc_o      <= id_pc_i;
      ex_ctrl_o    <= id_ctrl_i;
      ex_rs1_data_o<= id_rs1_data_i;
      ex_rs2_data_o<= id_rs2_data_i;
      ex_imm_o     <= id_imm_i;
    end
  end

  // ===========================================================================
  // EX/MEM 寄存器
  // ===========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mem_pc_o       <= 32'b0;
      mem_ctrl_o     <= ctrl_nop();
      mem_alu_result_o<= 32'b0;
      mem_rs2_data_o <= 32'b0;
      mem_imm_o      <= 32'b0;
    end else if (ex_mem_flush_i) begin
      mem_pc_o       <= 32'b0;
      mem_ctrl_o     <= ctrl_nop();
      mem_alu_result_o<= 32'b0;
      mem_rs2_data_o <= 32'b0;
      mem_imm_o      <= 32'b0;
    end else if (!ex_mem_stall_i) begin
      mem_pc_o       <= ex_pc_i;
      mem_ctrl_o     <= ex_ctrl_i;
      mem_alu_result_o<= ex_alu_result_i;
      mem_rs2_data_o <= ex_rs2_data_i;
      mem_imm_o      <= ex_imm_i;
    end
  end

  // ===========================================================================
  // MEM/WB 寄存器
  // ===========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_pc_o        <= 32'b0;
      wb_ctrl_o      <= ctrl_nop();
      wb_alu_result_o<= 32'b0;
      wb_rdata_o     <= 32'b0;
    end else if (mem_wb_flush_i) begin
      wb_pc_o        <= 32'b0;
      wb_ctrl_o      <= ctrl_nop();
      wb_alu_result_o<= 32'b0;
      wb_rdata_o     <= 32'b0;
    end else if (!mem_wb_stall_i) begin
      wb_pc_o        <= mem_pc_i;
      wb_ctrl_o      <= mem_ctrl_i;
      wb_alu_result_o<= mem_alu_result_i;
      wb_rdata_o     <= mem_rdata_i;
    end
  end

endmodule : rvp_pipeline_regs
