/**
 * rvp_hazard_unit.sv - RVP Hazard Detection Unit
 *
 * 冒险检测单元，检测流水线中的数据冒险和控制冒险，
 * 生成相应的stall和flush控制信号。
 *
 * 冒险类型:
 *   1. Load-Use冒险 (数据冒险):
 *      当ID阶段需要读取的寄存器正是EX阶段load指令的目标寄存器时，
 *      需要stall一个周期，等待load数据就绪。
 *   2. 分支冒险 (控制冒险):
 *      当分支跳转发生时，需要flush IF/ID流水线寄存器中
 *      错误取出的指令。
 *   3. 结构冒险:
 *      当内存接口忙时，需要stall取指阶段。
 *
 * 信号方向:
 *   - 接收各流水级的寄存器地址和控制信号
 *   - 输出stall信号到各级流水线寄存器
 *   - 输出flush信号到IF/ID流水线寄存器
 */

`include "rvp_config.svh"

module rvp_hazard_unit import rvp_pkg::*; (
    // ==========================================================================
    // 来自ID阶段 (译码) 的信号
    // ==========================================================================
    input  logic [REG_ADDR_W-1:0] id_rs1_addr_i,   // ID阶段rs1地址
    input  logic [REG_ADDR_W-1:0] id_rs2_addr_i,   // ID阶段rs2地址
    input  logic                  id_mem_read_i,   // ID阶段是否为load指令

    // ==========================================================================
    // 来自EX阶段 (执行) 的信号
    // ==========================================================================
    input  logic [REG_ADDR_W-1:0] ex_rd_addr_i,    // EX阶段目标寄存器地址
    input  logic                  ex_mem_read_i,   // EX阶段是否为load指令
    input  logic                  ex_reg_write_i,  // EX阶段是否写寄存器

    // ==========================================================================
    // 来自MEM阶段 (访存) 的信号
    // ==========================================================================
    input  logic [REG_ADDR_W-1:0] mem_rd_addr_i,   // MEM阶段目标寄存器地址
    input  logic                  mem_reg_write_i,  // MEM阶段是否写寄存器

    // ==========================================================================
    // 来自分支单元的信号 (控制冒险)
    // ==========================================================================
    input  logic                  branch_taken_i,   // 分支跳转信号
    input  logic                  jump_i,           // 无条件跳转信号

    // ==========================================================================
    // 来自内存接口的信号 (结构冒险)
    // ==========================================================================
    input  logic                  mem_stall_i,      // 内存忙导致stall

    // ==========================================================================
    // 输出: Stall信号 (各级流水线寄存器保持)
    // ==========================================================================
    output logic                  stall_if_o,       // IF阶段stall
    output logic                  stall_id_o,       // ID阶段stall
    output logic                  stall_ex_o,       // EX阶段stall
    output logic                  stall_mem_o,      // MEM阶段stall
    output logic                  stall_wb_o,       // WB阶段stall
    output logic                  pc_stall_o,       // PC寄存器stall

    // ==========================================================================
    // 输出: Flush信号 (流水线寄存器清零)
    // ==========================================================================
    output logic                  flush_if_o,       // IF阶段flush
    output logic                  flush_id_o,       // ID阶段flush
    output logic                  flush_ex_o,       // EX阶段flush
    output logic                  flush_mem_o,      // MEM阶段flush
    output logic                  flush_wb_o        // WB阶段flush
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号声明
  // ==========================================================================

  logic load_use_hazard;    // Load-Use冒险检测
  logic branch_hazard;      // 分支冒险检测
  logic any_stall;          // 任一stall条件成立

  // ==========================================================================
  // Load-Use冒险检测
  // ==========================================================================

  // 检测条件: ID阶段是load指令且其目标寄存器与ID阶段当前指令的源寄存器匹配
  // 此时需要stall一个周期让load数据就绪
  // TODO: 实现Load-Use冒险检测
  // assign load_use_hazard = ex_mem_read_i &&
  //   ((ex_rd_addr_i == id_rs1_addr_i) || (ex_rd_addr_i == id_rs2_addr_i)) &&
  //   (id_rs1_addr_i != 5'b0 || id_rs2_addr_i != 5'b0);

  // ==========================================================================
  // 分支冒险检测
  // ==========================================================================

  // 检测条件: 分支跳转或无条件跳转发生
  // 需要flush IF/ID流水线寄存器中的错误指令
  // TODO: assign branch_hazard = branch_taken_i | jump_i;

  // ==========================================================================
  // Stall信号生成
  // ==========================================================================

  // 任一stall条件成立
  // TODO: assign any_stall = load_use_hazard | mem_stall_i;

  // PC寄存器stall
  // TODO: assign pc_stall_o = any_stall;

  // IF阶段stall (取指停顿)
  // TODO: assign stall_if_o = any_stall;

  // ID阶段stall (译码停顿, 保持指令)
  // TODO: assign stall_id_o = any_stall;

  // EX/MEM/WB阶段在Load-Use冒险时不需要stall
  // 但在mem_stall时需要stall整个流水线
  // TODO: assign stall_ex_o  = mem_stall_i;
  // TODO: assign stall_mem_o = mem_stall_i;
  // TODO: assign stall_wb_o  = mem_stall_i;

  // ==========================================================================
  // Flush信号生成
  // ==========================================================================

  // 分支跳转时flush IF和ID阶段
  // TODO: assign flush_if_o = branch_hazard;
  // TODO: assign flush_id_o = branch_hazard;

  // Load-Use冒险时flush ID阶段 (实际上是插入bubble)
  // 当stall IF/ID同时，需要在EX阶段插入bubble
  // TODO: assign flush_ex_o = load_use_hazard;

  // MEM和WB阶段不需要flush (除非异常)
  // TODO: assign flush_mem_o = 1'b0;
  // TODO: assign flush_wb_o  = 1'b0;

  // ==========================================================================
  // 优先级处理
  // ==========================================================================
  // 注意: 当同时存在stall和flush时，flush优先级更高
  // 例如: 分支跳转时即使有stall也要flush
  // TODO: 处理stall和flush的优先级冲突

  // ==========================================================================
  // 调试信息 (可选)
  // ==========================================================================
`ifdef RVP_DEBUG
  // TODO: 输出调试信息
  // always_ff @(posedge clk_i) begin
  //   if (load_use_hazard) $display("HAZARD: Load-Use detected");
  //   if (branch_hazard)   $display("HAZARD: Branch taken, flushing pipeline");
  // end
`endif

endmodule
