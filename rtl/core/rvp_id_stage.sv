/**
 * rvp_id_stage.sv - RVP Instruction Decode Stage
 *
 * 译码阶段，负责指令译码、寄存器读取和立即数生成。
 * 参考ibex_id_stage.sv的设计。
 *
 * 主要功能:
 *   1. 指令译码 - 调用rvp_decoder生成控制信号
 *   2. 寄存器读取 - 调用rvp_register_file读取rs1和rs2
 *   3. 立即数生成 - 调用rvp_imm_generator生成立即数
 *   4. IF/ID流水线寄存器管理 - 锁存指令和PC
 *   5. 前递数据选择 - 根据前递信号选择数据源
 *
 * 数据流:
 *   IF → [IF/ID reg] → ID(译码+RF读取) → [ID/EX reg] → EX
 *
 * 内部子模块:
 *   - rvp_decoder       : 指令译码器
 *   - rvp_register_file : 寄存器堆 (2读1写)
 *   - rvp_imm_generator : 立即数生成器
 */

`include "rvp_config.svh"

module rvp_id_stage import rvp_pkg::*; #(
    parameter bit RV32E = 1'b0   // 1=RV32E (16 regs), 0=RV32I (32 regs)
) (
    // ==========================================================================
    // 时钟与复位
    // ==========================================================================
    input  logic              clk_i,           // 时钟
    input  logic              rst_ni,          // 异步低复位

    // ==========================================================================
    // 来自IF阶段的输入
    // ==========================================================================
    input  logic              instr_valid_i,   // 指令有效
    input  logic [31:0]       instr_i,        // 32位指令
    input  logic [31:0]       pc_i,            // 指令PC
    input  logic              instr_fetch_err_i, // 取指错误

    // ==========================================================================
    // 寄存器堆写回接口 (来自WB阶段)
    // ==========================================================================
    input  logic [REG_ADDR_W-1:0] wb_rd_addr_i,   // 写回寄存器地址
    input  logic [31:0]       wb_wdata_i,      // 写回数据
    input  logic              wb_rf_we_i,      // 写回使能

    // ==========================================================================
    // 输出到EX阶段
    // ==========================================================================
    output ctrl_signals_t    ctrl_signals_o,  // 控制信号
    output logic [31:0]       rs1_rdata_o,     // rs1读数据
    output logic [31:0]       rs2_rdata_o,     // rs2读数据
    output logic [31:0]       imm_o,           // 立即数
    output logic [31:0]       pc_o,            // PC (传递到EX)
    output logic [REG_ADDR_W-1:0] rs1_addr_o,  // rs1地址 (传递到EX/MEM)
    output logic [REG_ADDR_W-1:0] rs2_addr_o,  // rs2地址 (传递到EX/MEM)
    output logic [REG_ADDR_W-1:0] rd_addr_o,   // rd地址 (传递到EX/MEM/WB)
    output logic              instr_valid_o,   // 指令有效 (传递到EX)

    // ==========================================================================
    // 异常/特殊指令输出
    // ==========================================================================
    output logic              illegal_insn_o,  // 非法指令
    output logic              ecall_insn_o,    // ECALL指令
    output logic              ebreak_insn_o,   // EBREAK指令
    output logic              mret_insn_o,     // MRET指令
    output logic              wfi_insn_o,      // WFI指令

    // ==========================================================================
    // 前递输入 (条件编译)
    // ==========================================================================
`ifdef RVP_FORWARDING
    input  forward_sel_e     forward_a_i,     // rs1前递选择
    input  forward_sel_e     forward_b_i,     // rs2前递选择
    input  logic [31:0]       forward_a_data_i, // rs1前递数据
    input  logic [31:0]       forward_b_data_i, // rs2前递数据
`endif

    // ==========================================================================
    // 流水线控制信号
    // ==========================================================================
    input  logic              stall_i,        // 流水线停顿
    input  logic              flush_i         // 流水线刷新
);

  import rvp_pkg::*;

  // ==========================================================================
  // 内部信号声明
  // ==========================================================================

  // IF/ID流水线寄存器
  logic [31:0]       instr_q;          // 指令寄存器
  logic [31:0]       pc_q;              // PC寄存器
  logic              instr_valid_q;     // 指令有效寄存器

  // 译码器输出
  ctrl_signals_t     ctrl_signals;     // 控制信号
  logic [REG_ADDR_W-1:0] rs1_addr;     // rs1地址
  logic [REG_ADDR_W-1:0] rs2_addr;     // rs2地址
  logic [REG_ADDR_W-1:0] rd_addr;      // rd地址
  imm_type_e         imm_type;         // 立即数类型
  logic              illegal_insn;     // 非法指令
  logic              ecall_insn;       // ECALL
  logic              ebreak_insn;      // EBREAK
  logic              mret_insn;        // MRET
  logic              wfi_insn;         // WFI

  // 寄存器堆输出
  logic [31:0]       rf_rdata_a;       // rs1读数据
  logic [31:0]       rf_rdata_b;       // rs2读数据

  // 立即数生成器输出
  logic [31:0]       imm;              // 生成的立即数

  // 前递后的数据
  logic [31:0]       rs1_rdata_fwd;    // rs1前递后数据
  logic [31:0]       rs2_rdata_fwd;    // rs2前递后数据

  // ==========================================================================
  // IF/ID 流水线寄存器
  // ==========================================================================
  // TODO: 锁存IF阶段的指令和PC
  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     instr_q      <= 32'h0;
  //     pc_q          <= 32'h0;
  //     instr_valid_q <= 1'b0;
  //   end else if (flush_i) begin
  //     // Flush: 插入NOP
  //     instr_q      <= 32'h00000013;  // NOP
  //     instr_valid_q <= 1'b0;
  //   end else if (!stall_i) begin
  //     instr_q      <= instr_i;
  //     pc_q          <= pc_i;
  //     instr_valid_q <= instr_valid_i;
  //   end
  // end

  // ==========================================================================
  // 指令译码器实例化 (decoder)
  // ==========================================================================
  rvp_decoder #(
    .RV32E (RV32E)
  ) decoder_inst (
    .instr_i         (instr_q),
    .illegal_c_insn_i(1'b0),
    .ctrl_signals_o  (ctrl_signals),
    .rs1_addr_o      (rs1_addr),
    .rs2_addr_o      (rs2_addr),
    .rd_addr_o       (rd_addr),
    .imm_type_o      (imm_type),
    .illegal_insn_o  (illegal_insn),
    .ecall_insn_o    (ecall_insn),
    .ebreak_insn_o   (ebreak_insn),
    .mret_insn_o     (mret_insn),
    .wfi_insn_o      (wfi_insn)
  );

  // ==========================================================================
  // 立即数生成器实例化 (imm_generator)
  // ==========================================================================
  rvp_imm_generator imm_gen_inst (
    .instr_i    (instr_q),
    .imm_type_i (imm_type),
    .imm_o      (imm)
  );

  // ==========================================================================
  // 寄存器堆实例化 (register_file)
  // ==========================================================================
  rvp_register_file #(
    .RV32E     (RV32E),
    .DataWidth (REG_DATA_W)
  ) register_file_inst (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .test_en_i       (1'b0),
    .dummy_instr_id_i(1'b0),
    .dummy_instr_wb_i(1'b0),
    .raddr_a_i       (rs1_addr),
    .rdata_a_o       (rf_rdata_a),
    .raddr_b_i       (rs2_addr),
    .rdata_b_o       (rf_rdata_b),
    .waddr_a_i       (wb_rd_addr_i),
    .wdata_a_i       (wb_wdata_i),
    .we_a_i          (wb_rf_we_i)
  );

  // ==========================================================================
  // 前递数据选择 (条件编译)
  // ==========================================================================
`ifdef RVP_FORWARDING
  // rs1前递数据选择
  // TODO: always_comb begin
  //   unique case (forward_a_i)
  //     FWD_NONE:    rs1_rdata_fwd = rf_rdata_a;
  //     FWD_EX_MEM:  rs1_rdata_fwd = forward_a_data_i;
  //     FWD_MEM_WB:  rs1_rdata_fwd = forward_a_data_i;
  //     FWD_WB:      rs1_rdata_fwd = forward_a_data_i;
  //     default:     rs1_rdata_fwd = rf_rdata_a;
  //   endcase
  // end

  // rs2前递数据选择
  // TODO: always_comb begin
  //   unique case (forward_b_i)
  //     FWD_NONE:    rs2_rdata_fwd = rf_rdata_b;
  //     FWD_EX_MEM:  rs2_rdata_fwd = forward_b_data_i;
  //     FWD_MEM_WB:  rs2_rdata_fwd = forward_b_data_i;
  //     FWD_WB:      rs2_rdata_fwd = forward_b_data_i;
  //     default:     rs2_rdata_fwd = rf_rdata_b;
  //   endcase
  // end
`else
  // 无前递: 直接使用寄存器堆输出
  // TODO: assign rs1_rdata_fwd = rf_rdata_a;
  // TODO: assign rs2_rdata_fwd = rf_rdata_b;
`endif

  // ==========================================================================
  // 输出赋值
  // ==========================================================================

  // TODO: assign ctrl_signals_o = ctrl_signals;
  // TODO: assign rs1_rdata_o    = rs1_rdata_fwd;
  // TODO: assign rs2_rdata_o    = rs2_rdata_fwd;
  // TODO: assign imm_o          = imm;
  // TODO: assign pc_o           = pc_q;
  // TODO: assign rs1_addr_o     = rs1_addr;
  // TODO: assign rs2_addr_o     = rs2_addr;
  // TODO: assign rd_addr_o      = rd_addr;
  // TODO: assign instr_valid_o  = instr_valid_q;

  // 异常/特殊指令输出
  // TODO: assign illegal_insn_o = illegal_insn;
  // TODO: assign ecall_insn_o   = ecall_insn;
  // TODO: assign ebreak_insn_o  = ebreak_insn;
  // TODO: assign mret_insn_o    = mret_insn;
  // TODO: assign wfi_insn_o     = wfi_insn;

  // ==========================================================================
  // 调试信息 (可选)
  // ==========================================================================
`ifdef RVP_DEBUG
  // TODO: 输出调试信息
`endif

endmodule
