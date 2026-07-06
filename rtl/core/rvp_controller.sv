/**
 * rvp_controller.sv - RVP Main Controller
 *
 * 主控制器，包含核心的主FSM。负责处理复位、异常、中断和调试事件，
 * 生成流水线控制信号。
 * 参考ibex_controller.sv的ctrl_fsm_e设计。
 *
 * 主要功能:
 *   1. 复位序列管理 - 复位后进入正常取指执行流程
 *   2. 异常处理 - 处理非法指令、地址对齐错误等
 *   3. 中断处理 - 响应外部中断和软件中断
 *   4. 调试支持 - 响应调试请求，进入调试模式
 *   5. 流水线控制 - 生成stall/flush/pc_set等控制信号
 *
 * FSM状态:
 *   CTRL_RESET  - 复位状态，初始化所有寄存器
 *   CTRL_FETCH  - 正常取指状态
 *   CTRL_DECODE - 译码状态 (实际5级流水线中，DECODE与FETCH并行)
 *   CTRL_EXECUTE- 执行状态 (实际5级流水线中，EXECUTE与FETCH并行)
 *   CTRL_MEM    - 访存状态
 *   CTRL_WB     - 写回状态
 *   CTRL_STALL  - 流水线停顿状态
 *   CTRL_FLUSH  - 流水线刷新状态 (分支跳转或异常)
 */

`include "rvp_config.svh"

module rvp_controller import rvp_pkg::*; (
    // ==========================================================================
    // 时钟与复位
    // ==========================================================================
    input  logic              clk_i,           // 时钟
    input  logic              rst_ni,          // 异步低复位

    // ==========================================================================
    // 控制器状态输出
    // ==========================================================================
    output logic              ctrl_busy_o,    // 核心忙碌标志

    // ==========================================================================
    // 来自译码器的信号
    // ==========================================================================
    input  logic              illegal_insn_i,  // 非法指令
    input  logic              ecall_insn_i,    // ECALL指令
    input  logic              mret_insn_i,    // MRET指令
    input  logic              dret_insn_i,    // DRET指令 (调试返回)
    input  logic              wfi_insn_i,     // WFI指令 (等待中断)
    input  logic              ebrk_insn_i,    // EBREAK指令

    // ==========================================================================
    // 来自IF-ID流水线寄存器的信号
    // ==========================================================================
    input  logic              instr_valid_i,   // 指令有效
    input  logic [31:0]       instr_i,        // 指令内容 (用于mtval)
    input  logic [31:0]       pc_id_i,        // 指令地址

    // ==========================================================================
    // 输出到IF阶段 (取指控制)
    // ==========================================================================
    output logic              instr_req_o,    // 取指请求
    output logic              pc_set_o,       // PC设置信号 (跳转)
    output logic [2:0]        pc_sel_o,       // PC选择信号
    output logic [2:0]        exc_pc_mux_o,   // 异常PC选择
    output logic [5:0]        exc_cause_o,    // 异常原因编码

    // ==========================================================================
    // 来自LSU (访存单元) 的信号
    // ==========================================================================
    input  logic [31:0]       lsu_addr_last_i, // 最后访存地址 (用于mtval)
    input  logic              load_err_i,     // 加载错误
    input  logic              store_err_i,    // 存储错误

    // ==========================================================================
    // 来自分支单元的信号
    // ==========================================================================
    input  logic              branch_set_i,    // 分支跳转
    input  logic              jump_set_i,      // 无条件跳转

    // ==========================================================================
    // 中断信号
    // ==========================================================================
    input  logic              csr_mstatus_mie_i, // M模式中断使能
    input  logic              irq_pending_i,    // 中断挂起
    input  logic [14:0]       irqs_i,           // 中断请求向量
    input  logic              irq_nm_ext_i,     // 不可屏蔽中断
    output logic              nmi_mode_o,       // NMI处理模式

    // ==========================================================================
    // 调试信号
    // ==========================================================================
    input  logic              debug_req_i,      // 调试请求
    output logic [2:0]        debug_cause_o,    // 调试原因
    output logic              debug_csr_save_o,  // 保存CSR到调试上下文
    output logic              debug_mode_o,      // 当前处于调试模式
    output logic              debug_mode_entering_o, // 正在进入调试模式
    input  logic              debug_single_step_i,  // 单步调试模式
    input  logic              debug_ebreakm_i,  // M模式EBREAK触发调试
    input  logic              trigger_match_i,  // 触发器匹配

    // ==========================================================================
    // CSR控制信号
    // ==========================================================================
    output logic              csr_save_if_o,   // 保存IF阶段CSR
    output logic              csr_save_id_o,   // 保存ID阶段CSR
    output logic              csr_save_wb_o,   // 保存WB阶段CSR
    output logic              csr_restore_mret_id_o, // MRET恢复CSR
    output logic              csr_restore_dret_id_o, // DRET恢复CSR
    output logic              csr_save_cause_o, // 保存异常原因
    output logic [31:0]       csr_mtval_o,     // 异常trap值

    // ==========================================================================
    // 流水线Stall/Flush信号
    // ==========================================================================
    input  logic              stall_id_i,      // ID阶段stall
    input  logic              stall_wb_i,      // WB阶段stall
    output logic              flush_id_o,      // ID阶段flush
    input  logic              ready_wb_i,      // WB阶段就绪

    // ==========================================================================
    // 性能监控信号
    // ==========================================================================
    output logic              perf_jump_o,     // 跳转指令执行
    output logic              perf_tbranch_o   // 分支跳转执行
);

  import rvp_pkg::*;

  // ==========================================================================
  // FSM状态寄存器
  // ==========================================================================

  ctrl_state_e ctrl_fsm_cs, ctrl_fsm_ns;  // 当前状态, 下一状态

  // ==========================================================================
  // 内部状态寄存器
  // ==========================================================================

  logic        nmi_mode_q, nmi_mode_d;          // NMI模式
  logic        debug_mode_q, debug_mode_d;      // 调试模式
  logic [2:0]  debug_cause_d, debug_cause_q;    // 调试原因
  logic        debug_csr_save_d, debug_csr_save_q; // 调试CSR保存
  logic        pc_set_d, pc_set_q;              // PC设置

  // 异常相关信号
  logic        illegal_insn;    // 非法指令
  logic        exc_req;         // 异常请求
  logic        exc_req_lsu;     // LSU异常请求
  logic        exc_req_q;       // 异常请求寄存器

  // 中断相关信号
  logic        irq_req;         // 中断请求
  logic        irq_req_q;       // 中断请求寄存器

  // ==========================================================================
  // 异常请求生成
  // ==========================================================================

  // TODO: 合成异常请求信号
  // assign illegal_insn = illegal_insn_i;
  // assign exc_req = illegal_insn | ecall_insn_i |
  //                  load_err_i | store_err_i;
  // assign exc_req_lsu = load_err_i | store_err_i;

  // ==========================================================================
  // 中断请求生成
  // ==========================================================================

  // TODO: 检查中断条件
  // assign irq_req = irq_pending_i & csr_mstatus_mie_i;

  // ==========================================================================
  // 主FSM: 状态转移逻辑
  // ==========================================================================
  always_comb begin
    // 默认保持当前状态
    ctrl_fsm_ns = ctrl_fsm_cs;

    // 默认输出值
    instr_req_o          = 1'b1;
    pc_set_o             = 1'b0;
    pc_sel_o             = 3'b0;
    exc_pc_mux_o        = 3'b0;
    exc_cause_o          = 6'b0;
    flush_id_o           = 1'b0;
    nmi_mode_o           = nmi_mode_q;
    debug_mode_o         = debug_mode_q;
    debug_mode_entering_o = 1'b0;
    debug_cause_o        = debug_cause_q;
    debug_csr_save_o     = 1'b0;
    csr_save_if_o        = 1'b0;
    csr_save_id_o        = 1'b0;
    csr_save_wb_o        = 1'b0;
    csr_restore_mret_id_o = 1'b0;
    csr_restore_dret_id_o = 1'b0;
    csr_save_cause_o     = 1'b0;
    csr_mtval_o          = 32'b0;
    perf_jump_o          = 1'b0;
    perf_tbranch_o       = 1'b0;

    // TODO: 状态转移逻辑
    // unique case (ctrl_fsm_cs)
    //   CTRL_RESET: begin
    //     // 复位状态: 初始化完成后进入正常取指
    //     ctrl_fsm_ns = CTRL_FETCH;
    //     instr_req_o = 1'b0;
    //   end
    //
    //   CTRL_FETCH: begin
    //     // 正常取指状态
    //     if (debug_req_i || debug_single_step_i) begin
    //       // 调试请求: 进入调试模式
    //       ctrl_fsm_ns = CTRL_FLUSH;
    //       // TODO: 设置调试相关信号
    //     end else if (exc_req || irq_req) begin
    //       // 异常/中断: 刷新流水线
    //       ctrl_fsm_ns = CTRL_FLUSH;
    //       // TODO: 设置异常处理PC
    //     end else if (branch_set_i || jump_set_i) begin
    //       // 分支跳转: 刷新流水线
    //       ctrl_fsm_ns = CTRL_FLUSH;
    //       // TODO: 设置分支目标PC
    //     end
    //   end
    //
    //   CTRL_DECODE,
    //   CTRL_EXECUTE,
    //   CTRL_MEM,
    //   CTRL_WB: begin
    //     // 这些状态在流水线设计中实际并行运行
    //     // 状态机主要在FETCH和特殊状态间切换
    //     ctrl_fsm_ns = CTRL_FETCH;
    //   end
    //
    //   CTRL_STALL: begin
    //     // 流水线停顿: 等待stall解除
    //     if (!stall_id_i && !stall_wb_i) begin
    //       ctrl_fsm_ns = CTRL_FETCH;
    //     end
    //   end
    //
    //   CTRL_FLUSH: begin
    //     // 流水线刷新: 清除流水线后恢复正常
    //     ctrl_fsm_ns = CTRL_FETCH;
    //     flush_id_o  = 1'b1;
    //   end
    //
    //   default: begin
    //     ctrl_fsm_ns = CTRL_RESET;
    //   end
    // endcase
  end

  // ==========================================================================
  // 主FSM: 状态寄存器
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_fsm_cs <= CTRL_RESET;
      // TODO: 其他状态寄存器复位
      // nmi_mode_q      <= 1'b0;
      // debug_mode_q     <= 1'b0;
      // debug_cause_q    <= '0;
      // debug_csr_save_q <= 1'b0;
      // pc_set_q         <= 1'b0;
      // exc_req_q        <= 1'b0;
      // irq_req_q        <= 1'b0;
    end else begin
      ctrl_fsm_cs <= ctrl_fsm_ns;
      // TODO: 其他状态寄存器更新
      // nmi_mode_q      <= nmi_mode_d;
      // debug_mode_q     <= debug_mode_d;
      // debug_cause_q    <= debug_cause_d;
      // debug_csr_save_q <= debug_csr_save_d;
      // pc_set_q         <= pc_set_d;
      // exc_req_q        <= exc_req;
      // irq_req_q        <= irq_req;
    end
  end

  // ==========================================================================
  // 性能监控
  // ==========================================================================
  // TODO: 统计跳转和分支指令
  // assign perf_jump_o    = jump_set_i;
  // assign perf_tbranch_o = branch_set_i;

  // ==========================================================================
  // ctrl_busy 输出
  // ==========================================================================
  // TODO: assign ctrl_busy_o = (ctrl_fsm_cs != CTRL_RESET);

endmodule
