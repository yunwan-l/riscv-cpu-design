/**
 * rvp_forward_unit.sv - RVP Forwarding Unit
 *
 * 前递单元，检测EX阶段的源寄存器是否与后续流水级的目标寄存器匹配，
 * 如果匹配则生成前递选择信号，将较新的数据直接前递到EX阶段。
 *
 * 条件编译: 仅当RVP_FORWARDING=1时才实例化此模块。
 *           否则使用stall方式处理数据冒险。
 *
 * 前递路径:
 *   1. MEM→EX前递: 当EX阶段源寄存器与MEM阶段目标寄存器匹配时
 *      将MEM阶段ALU结果前递到EX阶段 (避免1周期stall)
 *   2. WB→EX前递: 当EX阶段源寄存器与WB阶段目标寄存器匹配时
 *      将WB阶段写回数据前递到EX阶段
 *
 * 前递优先级: MEM→EX > WB→EX (MEM阶段的数据更新)
 *
 * 参考: MIPS经典5级流水线前递逻辑
 */

`include "rvp_config.svh"

`ifdef RVP_FORWARDING  // 仅在启用前递时编译此模块

module rvp_forward_unit import rvp_pkg::*; (
    // ==========================================================================
    // EX阶段源寄存器信息
    // ==========================================================================
    input  logic [REG_ADDR_W-1:0] ex_rs1_addr_i,   // EX阶段rs1地址
    input  logic [REG_ADDR_W-1:0] ex_rs2_addr_i,   // EX阶段rs2地址

    // ==========================================================================
    // MEM阶段信息 (MEM→EX前递)
    // ==========================================================================
    input  logic [REG_ADDR_W-1:0] mem_rd_addr_i,   // MEM阶段目标寄存器地址
    input  logic                  mem_reg_write_i,  // MEM阶段是否写寄存器
    input  logic [31:0]           mem_alu_result_i, // MEM阶段ALU结果(前递数据)

    // ==========================================================================
    // WB阶段信息 (WB→EX前递)
    // ==========================================================================
    input  logic [REG_ADDR_W-1:0] wb_rd_addr_i,    // WB阶段目标寄存器地址
    input  logic                  wb_reg_write_i,   // WB阶段是否写寄存器
    input  logic [31:0]           wb_wdata_i,      // WB阶段写回数据(前递数据)

    // ==========================================================================
    // 输出: 前递选择信号
    // ==========================================================================
    output forward_sel_e          forward_a_o,      // rs1前递选择
    output forward_sel_e          forward_b_o,      // rs2前递选择
    output logic [31:0]           forward_a_data_o, // rs1前递数据
    output logic [31:0]           forward_b_data_o  // rs2前递数据
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号声明
  // ==========================================================================

  // rs1前递条件
  logic rs1_mem_forward;    // MEM→EX rs1前递条件
  logic rs1_wb_forward;     // WB→EX rs1前递条件

  // rs2前递条件
  logic rs2_mem_forward;    // MEM→EX rs2前递条件
  logic rs2_wb_forward;     // WB→EX rs2前递条件

  // ==========================================================================
  // MEM→EX前递检测 (优先级高)
  // ==========================================================================

  // rs1: EX阶段rs1地址与MEM阶段rd地址匹配，且MEM阶段写寄存器，且不是x0
  // TODO: assign rs1_mem_forward = mem_reg_write_i &&
  //          (mem_rd_addr_i != 5'b0) &&
  //          (mem_rd_addr_i == ex_rs1_addr_i);

  // rs2: EX阶段rs2地址与MEM阶段rd地址匹配，且MEM阶段写寄存器，且不是x0
  // TODO: assign rs2_mem_forward = mem_reg_write_i &&
  //          (mem_rd_addr_i != 5'b0) &&
  //          (mem_rd_addr_i == ex_rs2_addr_i);

  // ==========================================================================
  // WB→EX前递检测 (优先级低)
  // ==========================================================================

  // rs1: EX阶段rs1地址与WB阶段rd地址匹配，且WB阶段写寄存器，且不是x0
  //      且MEM阶段不前递(避免冲突)
  // TODO: assign rs1_wb_forward = wb_reg_write_i &&
  //          (wb_rd_addr_i != 5'b0) &&
  //          (wb_rd_addr_i == ex_rs1_addr_i) &&
  //          !rs1_mem_forward;

  // rs2: EX阶段rs2地址与WB阶段rd地址匹配，且WB阶段写寄存器，且不是x0
  //      且MEM阶段不前递(避免冲突)
  // TODO: assign rs2_wb_forward = wb_reg_write_i &&
  //          (wb_rd_addr_i != 5'b0) &&
  //          (wb_rd_addr_i == ex_rs2_addr_i) &&
  //          !rs2_mem_forward;

  // ==========================================================================
  // 前递选择信号生成
  // ==========================================================================

  // rs1前递选择
  // TODO: always_comb begin
  //   if (rs1_mem_forward)
  //     forward_a_o = FWD_EX_MEM;
  //   else if (rs1_wb_forward)
  //     forward_a_o = FWD_MEM_WB;
  //   else
  //     forward_a_o = FWD_NONE;
  // end

  // rs2前递选择
  // TODO: always_comb begin
  //   if (rs2_mem_forward)
  //     forward_b_o = FWD_EX_MEM;
  //   else if (rs2_wb_forward)
  //     forward_b_o = FWD_MEM_WB;
  //   else
  //     forward_b_o = FWD_NONE;
  // end

  // ==========================================================================
  // 前递数据选择
  // ==========================================================================

  // rs1前递数据
  // TODO: assign forward_a_data_o = rs1_mem_forward ? mem_alu_result_i : wb_wdata_i;

  // rs2前递数据
  // TODO: assign forward_b_data_o = rs2_mem_forward ? mem_alu_result_i : wb_wdata_i;

  // ==========================================================================
  // Load-Use冒险检测 (前递无法解决的冒险)
  // ==========================================================================
  // 当MEM阶段是load指令时，其结果在WB阶段才就绪，无法前递到EX
  // 此时仍需stall一个周期
  // 注意: 此检测也可在hazard_unit中进行

  // ==========================================================================
  // 设计说明
  // ==========================================================================
  // 1. 前递优先级: MEM→EX > WB→EX
  //    因为MEM阶段的数据比WB阶段更"新"
  // 2. x0寄存器不参与前递 (写入x0无意义)
  // 3. Load指令的结果在MEM阶段末才就绪，无法前递到同一周期的EX
  //    需要配合hazard_unit进行stall

endmodule

`endif // RVP_FORWARDING
