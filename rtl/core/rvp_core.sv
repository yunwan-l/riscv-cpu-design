/**
 * rvp_core.sv - RVP CPU Core Top-Level Module
 *
 * RVP处理器的核心顶层模块，实例化所有流水线阶段和控制单元。
 * 参考ibex_core.sv的端口定义风格。
 *
 * 流水线结构 (5级):
 *   IF (取指) → ID (译码) → EX (执行) → MEM (访存) → WB (写回)
 *
 * 内部实例化的模块:
 *   - rvp_if_stage      : 取指阶段
 *   - rvp_id_stage      : 译码阶段 (含decoder, register_file, imm_generator)
 *   - rvp_ex_stage       : 执行阶段 (含alu, branch_unit)
 *   - rvp_mem_stage      : 访存阶段
 *   - rvp_wb_stage       : 写回阶段
 *   - rvp_hazard_unit    : 冒险检测单元
 *   - rvp_forward_unit   : 前递单元 (条件实例化, RVP_FORWARDING=1时)
 *   - rvp_controller     : 主控制器
 *
 * 参数配置:
 *   - Pipeline配置: 流水线级数、写回阶段使能
 *   - Cache配置: I-Cache/D-Cache使能与参数
 *   - Forwarding配置: 前递使能
 *   - ISA配置: RV32I/RV32E, M扩展, C扩展
 */

`include "rvp_config.svh"

module rvp_core import rvp_pkg::*; #(
    // ==========================================================================
    // ISA配置
    // ==========================================================================
    parameter bit          RV32E          = 1'b0,   // 1=RV32E(16 regs), 0=RV32I(32 regs)
    parameter bit          RV32M          = 1'b0,   // 1=启用M扩展
    parameter bit          RV32C          = 1'b0,   // 1=启用C扩展(压缩指令)

    // ==========================================================================
    // 流水线配置
    // ==========================================================================
    parameter int unsigned PipelineStages  = 5,      // 流水线级数
    parameter bit          WritebackStage  = 1'b1,   // 1=5级(含WB), 0=4级(合并MEM+WB)
    parameter bit          BranchTargetALU = 1'b0,   // 1=专用分支目标ALU

    // ==========================================================================
    // 冒险处理配置
    // ==========================================================================
    parameter bit          Forwarding      = 1'b0,   // 1=启用前递, 0=仅stall
    parameter int unsigned BranchPredict   = 0,      // 0=none, 1=预测不跳转

    // ==========================================================================
    // Cache配置
    // ==========================================================================
    parameter bit          ICacheEnable    = 1'b0,   // 1=启用I-Cache
    parameter bit          DCacheEnable    = 1'b0,   // 1=启用D-Cache
    parameter int unsigned ICacheSizeBytes = 4096,   // I-Cache大小
    parameter int unsigned ICacheNumWays   = 2,      // I-Cache路数
    parameter int unsigned ICacheLineSize  = 64,     // I-Cache行大小(bits)

    // ==========================================================================
    // 调试配置
    // ==========================================================================
    parameter bit          DbgTriggerEn    = 1'b0,   // 1=启用调试触发器
    parameter int unsigned DbgHwBreakNum   = 1       // 硬件断点数量
) (
    // ==========================================================================
    // 时钟与复位
    // ==========================================================================
    input  logic              clk_i,           // 时钟
    input  logic              rst_ni,          // 异步低复位

    // ==========================================================================
    // 处理器配置
    // ==========================================================================
    input  logic [31:0]       hart_id_i,       // Hart ID (用于mhartid CSR)
    input  logic [31:0]       boot_addr_i,     // 启动地址 (复位PC)

    // ==========================================================================
    // 指令总线接口
    // ==========================================================================
    output logic              instr_req_o,     // 指令请求
    input  logic              instr_gnt_i,     // 指令授权
    input  logic              instr_rvalid_i,  // 指令有效
    output logic [31:0]       instr_addr_o,    // 指令地址
    input  logic [31:0]       instr_rdata_i,   // 指令数据
    input  logic              instr_err_i,     // 指令错误

    // ==========================================================================
    // 数据总线接口
    // ==========================================================================
    output logic              data_req_o,      // 数据请求
    input  logic              data_gnt_i,      // 数据授权
    input  logic              data_rvalid_i,   // 数据有效
    output logic              data_we_o,       // 数据写使能
    output logic [3:0]        data_be_o,       // 数据字节使能
    output logic [31:0]       data_addr_o,     // 数据地址
    output logic [31:0]       data_wdata_o,    // 数据写数据
    input  logic [31:0]       data_rdata_i,    // 数据读数据
    input  logic              data_err_i,       // 数据错误

    // ==========================================================================
    // 中断输入
    // ==========================================================================
    input  logic              irq_software_i,  // 软件中断
    input  logic              irq_timer_i,     // 定时器中断
    input  logic              irq_external_i,  // 外部中断
    input  logic [14:0]       irq_fast_i,     // 快速中断向量
    input  logic              irq_nm_i,        // 不可屏蔽中断(NMI)
    output logic              irq_pending_o,   // 中断挂起

    // ==========================================================================
    // 调试接口
    // ==========================================================================
    input  logic              debug_req_i,     // 调试请求
    output logic              crash_dump_o,    // 崩溃转储

    // ==========================================================================
    // 性能计数 (可选)
    // ==========================================================================
    output logic              perf_jump_o,     // 跳转指令计数
    output logic              perf_tbranch_o   // 分支跳转计数
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号: 流水线级间连接
  // ==========================================================================

  // IF → ID 接口
  logic [31:0]       if_id_instr;          // 指令
  logic [31:0]       if_id_pc;              // PC
  logic              if_id_instr_valid;     // 指令有效
  logic              if_id_fetch_err;      // 取指错误

  // ID → EX 接口
  ctrl_signals_t     id_ex_ctrl_signals;   // 控制信号
  logic [31:0]       id_ex_rs1_rdata;      // rs1数据
  logic [31:0]       id_ex_rs2_rdata;      // rs2数据
  logic [31:0]       id_ex_imm;            // 立即数
  logic [31:0]       id_ex_pc;              // PC
  logic [REG_ADDR_W-1:0] id_ex_rs1_addr;    // rs1地址
  logic [REG_ADDR_W-1:0] id_ex_rs2_addr;    // rs2地址
  logic [REG_ADDR_W-1:0] id_ex_rd_addr;     // rd地址
  logic              id_ex_instr_valid;     // 指令有效
  logic              id_ex_illegal_insn;    // 非法指令
  logic              id_ex_ecall_insn;      // ECALL
  logic              id_ex_ebreak_insn;     // EBREAK
  logic              id_ex_mret_insn;       // MRET
  logic              id_ex_wfi_insn;        // WFI

  // EX → MEM 接口
  logic [31:0]       ex_mem_alu_result;     // ALU结果
  logic [31:0]       ex_mem_wdata;          // 写数据
  logic              ex_mem_req;            // 内存请求
  logic              ex_mem_we;             // 写使能
  mem_size_e         ex_mem_size;           // 访问大小
  logic [31:0]       ex_mem_pc4;            // PC+4
  logic [REG_ADDR_W-1:0] ex_mem_rd_addr;    // rd地址
  logic              ex_mem_rf_we;          // 写使能
  wb_src_e           ex_mem_wb_src;         // 写回源
  logic              ex_mem_instr_valid;    // 指令有效

  // MEM → WB 接口
  logic [31:0]       mem_wb_alu_result;     // ALU结果
  logic [31:0]       mem_wb_rdata;          // 读数据
  logic [31:0]       mem_wb_pc4;            // PC+4
  logic [REG_ADDR_W-1:0] mem_wb_rd_addr;    // rd地址
  logic              mem_wb_rf_we;          // 写使能
  wb_src_e           mem_wb_wb_src;         // 写回源
  logic              mem_wb_instr_valid;    // 指令有效

  // WB → ID 接口 (寄存器堆写回)
  logic [REG_ADDR_W-1:0] wb_id_rd_addr;    // 写回地址
  logic [31:0]       wb_id_wdata;           // 写回数据
  logic              wb_id_rf_we;           // 写使能

  // ==========================================================================
  // 内部信号: 分支/跳转
  // ==========================================================================

  logic              branch_taken;          // 分支跳转
  logic [31:0]       branch_target;         // 分支目标

  // ==========================================================================
  // 内部信号: 冒险检测
  // ==========================================================================

  logic              stall_if;              // IF stall
  logic              stall_id;              // ID stall
  logic              stall_ex;              // EX stall
  logic              stall_mem;             // MEM stall
  logic              stall_wb;              // WB stall
  logic              pc_stall;              // PC stall
  logic              flush_if;              // IF flush
  logic              flush_id;              // ID flush
  logic              flush_ex;              // EX flush
  logic              flush_mem;             // MEM flush
  logic              flush_wb;              // WB flush
  logic              mem_stall;             // 内存接口stall

  // ==========================================================================
  // 内部信号: 前递 (条件编译)
  // ==========================================================================
`ifdef RVP_FORWARDING
  forward_sel_e      forward_a;             // rs1前递选择
  forward_sel_e      forward_b;             // rs2前递选择
  logic [31:0]       forward_a_data;        // rs1前递数据
  logic [31:0]       forward_b_data;        // rs2前递数据
`endif

  // ==========================================================================
  // 内部信号: 控制器
  // ==========================================================================

  logic              ctrl_busy;            // 控制器忙碌
  logic              ctrl_instr_req;       // 取指请求
  logic              ctrl_pc_set;          // PC设置
  logic [2:0]        ctrl_pc_sel;          // PC选择
  logic [2:0]        ctrl_exc_pc_mux;      // 异常PC选择
  logic [5:0]        ctrl_exc_cause;       // 异常原因
  logic              ctrl_flush_id;        // ID flush
  logic              ctrl_nmi_mode;        // NMI模式
  logic              ctrl_debug_mode;       // 调试模式
  logic [2:0]        ctrl_debug_cause;     // 调试原因
  logic              ctrl_debug_csr_save;   // 调试CSR保存
  logic              ctrl_debug_entering;   // 正在进入调试
  logic              ctrl_csr_save_if;      // 保存IF CSR
  logic              ctrl_csr_save_id;      // 保存ID CSR
  logic              ctrl_csr_save_wb;      // 保存WB CSR
  logic              ctrl_csr_restore_mret; // MRET恢复CSR
  logic              ctrl_csr_restore_dret; // DRET恢复CSR
  logic              ctrl_csr_save_cause;   // 保存异常原因
  logic [31:0]       ctrl_csr_mtval;       // 异常trap值
  logic              ctrl_perf_jump;       // 跳转性能计数
  logic              ctrl_perf_tbranch;    // 分支性能计数

  // ==========================================================================
  // 取指阶段实例化 (IF Stage)
  // ==========================================================================
  rvp_if_stage #(
    .ICacheEnable    (ICacheEnable),
    .ICacheSizeBytes (ICacheSizeBytes),
    .ICacheNumWays   (ICacheNumWays),
    .ICacheLineSize  (ICacheLineSize)
  ) if_stage_inst (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .boot_addr_i      (boot_addr_i),
    .pc_src_i         (branch_target),
    .pc_sel_i         (ctrl_pc_sel),
    .pc_set_i         (ctrl_pc_set),
    .exc_pc_mux_i     (ctrl_exc_pc_mux),
    .instr_req_o      (instr_req_o),
    .instr_gnt_i      (instr_gnt_i),
    .instr_rvalid_i   (instr_rvalid_i),
    .instr_addr_o     (instr_addr_o),
    .instr_rdata_i    (instr_rdata_i),
    .instr_rdata_o    (if_id_instr),
    .pc_o             (if_id_pc),
    .instr_valid_o    (if_id_instr_valid),
    .instr_fetch_err_o(if_id_fetch_err),
    .stall_i          (stall_if),
    .flush_i          (flush_if),
    .debug_req_i      (debug_req_i)
  );

  // ==========================================================================
  // 译码阶段实例化 (ID Stage)
  // ==========================================================================
  rvp_id_stage #(
    .RV32E (RV32E)
  ) id_stage_inst (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .instr_valid_i    (if_id_instr_valid),
    .instr_i          (if_id_instr),
    .pc_i             (if_id_pc),
    .instr_fetch_err_i(if_id_fetch_err),
    .wb_rd_addr_i     (wb_id_rd_addr),
    .wb_wdata_i       (wb_id_wdata),
    .wb_rf_we_i       (wb_id_rf_we),
    .ctrl_signals_o   (id_ex_ctrl_signals),
    .rs1_rdata_o      (id_ex_rs1_rdata),
    .rs2_rdata_o      (id_ex_rs2_rdata),
    .imm_o            (id_ex_imm),
    .pc_o             (id_ex_pc),
    .rs1_addr_o       (id_ex_rs1_addr),
    .rs2_addr_o       (id_ex_rs2_addr),
    .rd_addr_o        (id_ex_rd_addr),
    .instr_valid_o    (id_ex_instr_valid),
    .illegal_insn_o   (id_ex_illegal_insn),
    .ecall_insn_o     (id_ex_ecall_insn),
    .ebreak_insn_o    (id_ex_ebreak_insn),
    .mret_insn_o      (id_ex_mret_insn),
    .wfi_insn_o       (id_ex_wfi_insn),
`ifdef RVP_FORWARDING
    .forward_a_i      (forward_a),
    .forward_b_i      (forward_b),
    .forward_a_data_i (forward_a_data),
    .forward_b_data_i (forward_b_data),
`endif
    .stall_i          (stall_id),
    .flush_i          (flush_id)
  );

  // ==========================================================================
  // 执行阶段实例化 (EX Stage)
  // ==========================================================================
  rvp_ex_stage ex_stage_inst (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .ctrl_signals_i   (id_ex_ctrl_signals),
    .rs1_rdata_i      (id_ex_rs1_rdata),
    .rs2_rdata_i      (id_ex_rs2_rdata),
    .imm_i            (id_ex_imm),
    .pc_i             (id_ex_pc),
    .rs1_addr_i       (id_ex_rs1_addr),
    .rs2_addr_i       (id_ex_rs2_addr),
    .rd_addr_i        (id_ex_rd_addr),
    .instr_valid_i    (id_ex_instr_valid),
`ifdef RVP_FORWARDING
    .forward_a_i      (forward_a),
    .forward_b_i      (forward_b),
    .forward_a_data_i (forward_a_data),
    .forward_b_data_i (forward_b_data),
`endif
    .alu_op_i         (id_ex_ctrl_signals.alu_op),
    .alu_src_a_i      (id_ex_ctrl_signals.alu_src_a),
    .alu_src_b_i      (id_ex_ctrl_signals.alu_src_b),
    .alu_result_o     (ex_mem_alu_result),
    .alu_result_valid_o(),
    .mem_addr_o       (),
    .mem_wdata_o      (ex_mem_wdata),
    .mem_req_o        (ex_mem_req),
    .mem_we_o         (ex_mem_we),
    .mem_size_o       (ex_mem_size),
    .pc4_o            (ex_mem_pc4),
    .rd_addr_o        (ex_mem_rd_addr),
    .rf_we_o          (ex_mem_rf_we),
    .wb_src_o         (ex_mem_wb_src),
    .instr_valid_o    (ex_mem_instr_valid),
    .branch_taken_o   (branch_taken),
    .branch_target_o  (branch_target),
    .stall_i          (stall_ex),
    .flush_i          (flush_ex)
  );

  // ==========================================================================
  // 访存阶段实例化 (MEM Stage)
  // ==========================================================================
  rvp_mem_stage mem_stage_inst (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .alu_result_i     (ex_mem_alu_result),
    .mem_wdata_i      (ex_mem_wdata),
    .mem_req_i        (ex_mem_req),
    .mem_we_i         (ex_mem_we),
    .mem_size_i       (ex_mem_size),
    .pc4_i            (ex_mem_pc4),
    .rd_addr_i        (ex_mem_rd_addr),
    .rf_we_i          (ex_mem_rf_we),
    .wb_src_i         (ex_mem_wb_src),
    .instr_valid_i    (ex_mem_instr_valid),
    .mem_req_o        (data_req_o),
    .mem_gnt_i        (data_gnt_i),
    .mem_rvalid_i     (data_rvalid_i),
    .mem_addr_o       (data_addr_o),
    .mem_wdata_o      (data_wdata_o),
    .mem_rdata_i      (data_rdata_i),
    .mem_we_o         (data_we_o),
    .mem_be_o         (data_be_o),
    .alu_result_o     (mem_wb_alu_result),
    .mem_rdata_o      (mem_wb_rdata),
    .pc4_o            (mem_wb_pc4),
    .rd_addr_o        (mem_wb_rd_addr),
    .rf_we_o          (mem_wb_rf_we),
    .wb_src_o         (mem_wb_wb_src),
    .instr_valid_o    (mem_wb_instr_valid),
    .load_err_o       (),
    .store_err_o      (),
    .stall_i          (stall_mem),
    .flush_i          (flush_mem)
  );

  // ==========================================================================
  // 写回阶段实例化 (WB Stage)
  // ==========================================================================
  rvp_wb_stage wb_stage_inst (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .wb_src_i         (mem_wb_wb_src),
    .alu_result_i     (mem_wb_alu_result),
    .mem_rdata_i      (mem_wb_rdata),
    .pc4_i            (mem_wb_pc4),
    .csr_rdata_i      (32'b0),   // TODO: 连接CSR读数据
    .rd_addr_i        (mem_wb_rd_addr),
    .rf_we_i          (mem_wb_rf_we),
    .stall_i          (stall_wb),
    .flush_i          (flush_wb),
    .rd_addr_o        (wb_id_rd_addr),
    .rd_wdata_o       (wb_id_wdata),
    .rf_we_o          (wb_id_rf_we),
    .wb_forward_data_o(),
    .wb_valid_o       ()
  );

  // ==========================================================================
  // 冒险检测单元实例化 (Hazard Unit)
  // ==========================================================================
  rvp_hazard_unit hazard_unit_inst (
    .id_rs1_addr_i    (id_ex_rs1_addr),
    .id_rs2_addr_i    (id_ex_rs2_addr),
    .id_mem_read_i    (id_ex_ctrl_signals.mem_read),
    .ex_rd_addr_i     (ex_mem_rd_addr),
    .ex_mem_read_i    (ex_mem_req & ~ex_mem_we),
    .ex_reg_write_i   (ex_mem_rf_we),
    .mem_rd_addr_i    (mem_wb_rd_addr),
    .mem_reg_write_i  (mem_wb_rf_we),
    .branch_taken_i   (branch_taken),
    .jump_i           (id_ex_ctrl_signals.jump),
    .mem_stall_i      (mem_stall),
    .stall_if_o       (stall_if),
    .stall_id_o       (stall_id),
    .stall_ex_o       (stall_ex),
    .stall_mem_o      (stall_mem),
    .stall_wb_o       (stall_wb),
    .pc_stall_o       (pc_stall),
    .flush_if_o       (flush_if),
    .flush_id_o       (flush_id),
    .flush_ex_o       (flush_ex),
    .flush_mem_o      (flush_mem),
    .flush_wb_o       (flush_wb)
  );

  // ==========================================================================
  // 前递单元实例化 (Forward Unit) - 条件编译
  // ==========================================================================
`ifdef RVP_FORWARDING
  rvp_forward_unit forward_unit_inst (
    .ex_rs1_addr_i    (id_ex_rs1_addr),
    .ex_rs2_addr_i    (id_ex_rs2_addr),
    .mem_rd_addr_i    (ex_mem_rd_addr),
    .mem_reg_write_i  (ex_mem_rf_we),
    .mem_alu_result_i (ex_mem_alu_result),
    .wb_rd_addr_i     (mem_wb_rd_addr),
    .wb_reg_write_i   (mem_wb_rf_we),
    .wb_wdata_i       (wb_id_wdata),
    .forward_a_o      (forward_a),
    .forward_b_o      (forward_b),
    .forward_a_data_o (forward_a_data),
    .forward_b_data_o (forward_b_data)
  );
`endif

  // ==========================================================================
  // 控制器实例化 (Controller)
  // ==========================================================================
  rvp_controller controller_inst (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .ctrl_busy_o      (ctrl_busy),
    .illegal_insn_i   (id_ex_illegal_insn),
    .ecall_insn_i     (id_ex_ecall_insn),
    .mret_insn_i      (id_ex_mret_insn),
    .dret_insn_i      (1'b0),
    .wfi_insn_i       (id_ex_wfi_insn),
    .ebrk_insn_i      (id_ex_ebreak_insn),
    .instr_valid_i    (id_ex_instr_valid),
    .instr_i          (if_id_instr),
    .pc_id_i          (id_ex_pc),
    .instr_req_o      (ctrl_instr_req),
    .pc_set_o         (ctrl_pc_set),
    .pc_sel_o         (ctrl_pc_sel),
    .exc_pc_mux_o     (ctrl_exc_pc_mux),
    .exc_cause_o      (ctrl_exc_cause),
    .lsu_addr_last_i  (data_addr_o),
    .load_err_i       (1'b0),
    .store_err_i      (1'b0),
    .branch_set_i     (branch_taken),
    .jump_set_i       (id_ex_ctrl_signals.jump),
    .csr_mstatus_mie_i(1'b0),
    .irq_pending_i    (irq_software_i | irq_timer_i | irq_external_i),
    .irqs_i           (irq_fast_i),
    .irq_nm_ext_i     (irq_nm_i),
    .nmi_mode_o       (ctrl_nmi_mode),
    .debug_req_i      (debug_req_i),
    .debug_cause_o    (ctrl_debug_cause),
    .debug_csr_save_o (ctrl_debug_csr_save),
    .debug_mode_o     (ctrl_debug_mode),
    .debug_mode_entering_o (ctrl_debug_entering),
    .debug_single_step_i (1'b0),
    .debug_ebreakm_i  (1'b0),
    .trigger_match_i  (1'b0),
    .csr_save_if_o    (ctrl_csr_save_if),
    .csr_save_id_o    (ctrl_csr_save_id),
    .csr_save_wb_o    (ctrl_csr_save_wb),
    .csr_restore_mret_id_o (ctrl_csr_restore_mret),
    .csr_restore_dret_id_o (ctrl_csr_restore_dret),
    .csr_save_cause_o (ctrl_csr_save_cause),
    .csr_mtval_o      (ctrl_csr_mtval),
    .stall_id_i       (stall_id),
    .stall_wb_i       (stall_wb),
    .flush_id_o       (ctrl_flush_id),
    .ready_wb_i       (~stall_wb),
    .perf_jump_o      (ctrl_perf_jump),
    .perf_tbranch_o   (ctrl_perf_tbranch)
  );

  // ==========================================================================
  // 顶层输出赋值
  // ==========================================================================

  // 中断挂起输出
  // TODO: assign irq_pending_o = irq_software_i | irq_timer_i | irq_external_i;

  // 崩溃转储 (暂不支持)
  // TODO: assign crash_dump_o = 1'b0;

  // 性能计数输出
  // TODO: assign perf_jump_o    = ctrl_perf_jump;
  // TODO: assign perf_tbranch_o = ctrl_perf_tbranch;

  // 内存接口stall信号 (从数据总线响应生成)
  // TODO: assign mem_stall = data_req_o & ~data_gnt_i;

  // ==========================================================================
  // 断言 (可选)
  // ==========================================================================
  // TODO: 添加关键信号的断言检查

endmodule
