/**
 * rvp_controller.sv - RVP Main Controller
 *
 * 主控制器，负责处理复位、异常、中断和调试事件，
 * 生成流水线控制信号。
 *
 * 主要功能:
 *   1. 复位序列管理
 *   2. 异常处理 (非法指令、地址对齐错误)
 *   3. 中断处理
 *   4. 流水线控制 (stall/flush/pc_set)
 */

`include "rvp_config.svh"

module rvp_controller import rvp_pkg::*; (
    input  logic              clk_i,
    input  logic              rst_ni,

    // 控制器状态输出
    output logic              ctrl_busy_o,

    // 来自译码器的信号
    input  logic              illegal_insn_i,
    input  logic              ecall_insn_i,
    input  logic              mret_insn_i,
    input  logic              dret_insn_i,
    input  logic              wfi_insn_i,
    input  logic              ebrk_insn_i,

    // 来自IF-ID流水线寄存器的信号
    input  logic              instr_valid_i,
    input  logic [31:0]       instr_i,
    input  logic [31:0]       pc_id_i,

    // 输出到IF阶段
    output logic              instr_req_o,
    output logic              pc_set_o,
    output logic [2:0]        pc_sel_o,
    output logic [2:0]        exc_pc_mux_o,
    output logic [5:0]        exc_cause_o,

    // 来自LSU的信号
    input  logic [31:0]       lsu_addr_last_i,
    input  logic              load_err_i,
    input  logic              store_err_i,

    // 来自分支单元的信号
    input  logic              branch_set_i,
    input  logic              jump_set_i,

    // 中断信号
    input  logic              csr_mstatus_mie_i,
    input  logic              irq_pending_i,
    input  logic [14:0]       irqs_i,
    input  logic              irq_nm_ext_i,
    output logic              nmi_mode_o,

    // 调试信号
    input  logic              debug_req_i,
    output logic [2:0]        debug_cause_o,
    output logic              debug_csr_save_o,
    output logic              debug_mode_o,
    output logic              debug_mode_entering_o,
    input  logic              debug_single_step_i,
    input  logic              debug_ebreakm_i,
    input  logic              trigger_match_i,

    // CSR控制信号
    output logic              csr_save_if_o,
    output logic              csr_save_id_o,
    output logic              csr_save_wb_o,
    output logic              csr_restore_mret_id_o,
    output logic              csr_restore_dret_id_o,
    output logic              csr_save_cause_o,
    output logic [31:0]       csr_mtval_o,

    // 流水线Stall/Flush信号
    input  logic              stall_id_i,
    input  logic              stall_wb_i,
    output logic              flush_id_o,
    input  logic              ready_wb_i,

    // 性能监控
    output logic              perf_jump_o,
    output logic              perf_tbranch_o
);

  import rvp_pkg::*;

  // ==========================================================================
  // FSM状态寄存器
  // ==========================================================================
  ctrl_state_e ctrl_fsm_cs, ctrl_fsm_ns;

  // 内部状态寄存器
  logic        nmi_mode_q;
  logic        debug_mode_q;
  logic [2:0]  debug_cause_q;

  // 异常相关信号
  logic        exc_req;
  logic        exc_req_lsu;

  // 中断相关信号
  logic        irq_req;

  // ==========================================================================
  // 异常请求生成
  // ==========================================================================

  assign exc_req_lsu = load_err_i | store_err_i;
  assign exc_req     = illegal_insn_i | ecall_insn_i | ebrk_insn_i |
                       load_err_i | store_err_i;

  // ==========================================================================
  // 中断请求生成
  // ==========================================================================

  assign irq_req = irq_pending_i & csr_mstatus_mie_i;

  // ==========================================================================
  // 主FSM: 状态转移逻辑
  // ==========================================================================
  always_comb begin
    ctrl_fsm_ns = ctrl_fsm_cs;

    // 默认输出值
    instr_req_o          = 1'b1;
    pc_set_o             = 1'b0;
    pc_sel_o             = 3'b1;      // 默认: PC+4 (顺序取指)
    exc_pc_mux_o         = 3'b0;
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

    unique case (ctrl_fsm_cs)
      CTRL_RESET: begin
        // 复位状态: 初始化，PC选择启动地址
        ctrl_fsm_ns = CTRL_FETCH;
        instr_req_o = 1'b0;
        pc_sel_o    = 3'b0;  // PC_SEL_BOOT
      end

      CTRL_FETCH: begin
        // 正常取指: PC = PC+4
        pc_sel_o = 3'b1;  // PC_SEL_PC4

        if (debug_req_i || debug_single_step_i) begin
          ctrl_fsm_ns = CTRL_FLUSH;
          debug_mode_entering_o = 1'b1;
          debug_csr_save_o = 1'b1;
          pc_set_o = 1'b1;
        end else if (irq_nm_ext_i) begin
          // 不可屏蔽中断
          ctrl_fsm_ns = CTRL_FLUSH;
          pc_set_o = 1'b1;
          pc_sel_o = 3'd3;  // PC_SEL_EXC (异常向量)
          exc_cause_o = 6'd0;
          nmi_mode_o = 1'b1;
        end else if (irq_req && !nmi_mode_q) begin
          // 外部中断
          ctrl_fsm_ns = CTRL_FLUSH;
          pc_set_o = 1'b1;
          pc_sel_o = 3'd3;
          exc_cause_o = 6'd11;  // Machine external interrupt
          csr_save_if_o = 1'b1;
          csr_save_id_o = 1'b1;
          csr_save_cause_o = 1'b1;
        end else if (exc_req && instr_valid_i) begin
          // 异常处理
          ctrl_fsm_ns = CTRL_FLUSH;
          pc_set_o = 1'b1;
          pc_sel_o = 3'd3;
          flush_id_o = 1'b1;
          csr_save_if_o = 1'b1;
          csr_save_id_o = 1'b1;
          csr_save_cause_o = 1'b1;

          if (ecall_insn_i)
            exc_cause_o = 6'd11;  // Environment call from M-mode
          else if (illegal_insn_i)
            exc_cause_o = 6'd2;   // Illegal instruction
          else if (load_err_i)
            exc_cause_o = 6'd4;   // Load address misaligned
          else if (store_err_i)
            exc_cause_o = 6'd6;   // Store address misaligned

          csr_mtval_o = exc_req_lsu ? lsu_addr_last_i : pc_id_i;
        end else if (mret_insn_i) begin
          // MRET: 从异常返回
          ctrl_fsm_ns = CTRL_FLUSH;
          pc_set_o = 1'b1;
          pc_sel_o = 3'd2;  // 跳转到mepc
          csr_restore_mret_id_o = 1'b1;
          flush_id_o = 1'b1;
          if (nmi_mode_q) nmi_mode_o = 1'b0;
        end else if (branch_set_i) begin
          // Branch taken in EX: flush pipeline, redirect PC
          // Note: jump_set_i from ID is intentionally NOT handled here.
          // JAL/JALR must reach EX for branch target computation.
          // The hazard unit handles flushing via branch_hazard when EX stage
          // reports branch_taken. Premature flushing in ID uses stale target.
          ctrl_fsm_ns = CTRL_FLUSH;
          pc_set_o = 1'b1;
          pc_sel_o = 3'd2;
          flush_id_o = 1'b1;
        end
      end

      CTRL_STALL: begin
        // 流水线停顿: 等待stall解除
        if (!stall_id_i && !stall_wb_i)
          ctrl_fsm_ns = CTRL_FETCH;
      end

      CTRL_FLUSH: begin
        // 流水线刷新: 清除后恢复正常
        ctrl_fsm_ns = CTRL_FETCH;
        flush_id_o = 1'b1;
      end

      default: begin
        ctrl_fsm_ns = CTRL_RESET;
      end
    endcase
  end

  // ==========================================================================
  // 主FSM: 状态寄存器
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_fsm_cs   <= CTRL_RESET;
      nmi_mode_q    <= 1'b0;
      debug_mode_q  <= 1'b0;
      debug_cause_q <= 3'b0;
    end else begin
      ctrl_fsm_cs   <= ctrl_fsm_ns;
      nmi_mode_q    <= nmi_mode_o;
      debug_mode_q  <= (ctrl_fsm_ns == CTRL_FLUSH) ? debug_mode_q : 1'b0;
      debug_cause_q <= debug_cause_o;
    end
  end

  // ==========================================================================
  // 性能监控 (持续赋值，不受FSM状态影响)
  // ==========================================================================
  always_comb begin
    perf_jump_o    = jump_set_i;
    perf_tbranch_o = branch_set_i;
  end

  // ==========================================================================
  // ctrl_busy 输出
  // ==========================================================================
  assign ctrl_busy_o = (ctrl_fsm_cs == CTRL_RESET);

endmodule
