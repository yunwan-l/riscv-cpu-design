/**
 * rvp_ex_stage.sv - RVP Execute Stage
 *
 * 执行阶段，负责ALU运算、分支判定和跳转目标计算。
 * 参考ibex_ex_block.sv的设计。
 *
 * 主要功能:
 *   1. ALU运算 - 执行算术、逻辑、移位等操作
 *   2. 分支判定 - 判定条件分支是否跳转
 *   3. 跳转目标计算 - 计算JAL/JALR/分支目标地址
 *   4. 操作数选择 - 从寄存器值、立即数、PC中选择ALU操作数
 *   5. 前递数据选择 - 根据前递信号选择操作数来源 (条件编译)
 *
 * 数据流:
 *   ID → [ID/EX reg] → EX(ALU+Branch) → [EX/MEM reg] → MEM
 *
 * 内部子模块:
 *   - rvp_alu         : 算术逻辑单元
 *   - rvp_branch_unit : 分支判定单元
 *   - forward_mux     : 前递多路选择器 (条件编译)
 */

`include "rvp_config.svh"

module rvp_ex_stage import rvp_pkg::*; (
    // ==========================================================================
    // 时钟与复位
    // ==========================================================================
    input  logic              clk_i,           // 时钟
    input  logic              rst_ni,          // 异步低复位

    // ==========================================================================
    // 来自ID阶段的输入
    // ==========================================================================
    input  ctrl_signals_t    ctrl_signals_i,  // 控制信号
    input  logic [31:0]       rs1_rdata_i,     // rs1读数据
    input  logic [31:0]       rs2_rdata_i,     // rs2读数据
    input  logic [31:0]       imm_i,          // 立即数
    input  logic [31:0]       pc_i,            // 当前PC
    input  logic [REG_ADDR_W-1:0] rs1_addr_i,  // rs1地址
    input  logic [REG_ADDR_W-1:0] rs2_addr_i,  // rs2地址
    input  logic [REG_ADDR_W-1:0] rd_addr_i,   // rd地址
    input  logic              instr_valid_i,   // 指令有效

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
    // ALU操作数 (简化接口)
    // ==========================================================================
    input  alu_op_e           alu_op_i,        // ALU操作选择
    input  logic              alu_src_a_i,     // 操作数A源: 0=rs1, 1=PC
    input  logic              alu_src_b_i,     // 操作数B源: 0=rs2, 1=imm

    // ==========================================================================
    // 输出到MEM阶段
    // ==========================================================================
    output logic [31:0]       alu_result_o,    // ALU结果
    output logic              alu_result_valid_o, // ALU结果有效
    output logic [31:0]       mem_addr_o,      // 内存地址 (ALU结果)
    output logic [31:0]       mem_wdata_o,     // 内存写数据 (rs2值)
    output logic              mem_req_o,        // 内存请求
    output logic              mem_we_o,         // 内存写使能
    output mem_size_e         mem_size_o,       // 内存访问大小
    output logic [31:0]       pc4_o,           // PC+4 (返回地址)
    output logic [REG_ADDR_W-1:0] rd_addr_o,   // rd地址 (传递到MEM/WB)
    output logic              rf_we_o,         // 寄存器写使能
    output wb_src_e           wb_src_o,        // 写回源选择
    output logic              instr_valid_o,   // 指令有效 (传递到MEM)

    // ==========================================================================
    // 分支输出 (到IF阶段/控制器)
    // ==========================================================================
    output logic              branch_taken_o,   // 分支跳转信号
    output logic [31:0]       branch_target_o,  // 分支目标地址

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

  // ID/EX流水线寄存器
  ctrl_signals_t      ctrl_signals_q;    // 控制信号寄存器
  logic [31:0]        rs1_rdata_q;       // rs1数据寄存器
  logic [31:0]        rs2_rdata_q;       // rs2数据寄存器
  logic [31:0]        imm_q;             // 立即数寄存器
  logic [31:0]        pc_q;              // PC寄存器
  logic [REG_ADDR_W-1:0] rs1_addr_q;     // rs1地址寄存器
  logic [REG_ADDR_W-1:0] rs2_addr_q;     // rs2地址寄存器
  logic [REG_ADDR_W-1:0] rd_addr_q;      // rd地址寄存器
  logic               instr_valid_q;     // 指令有效寄存器

  // ALU操作数
  logic [31:0]        operand_a;         // ALU操作数A
  logic [31:0]        operand_b;         // ALU操作数B

  // 前递后的操作数
  logic [31:0]        operand_a_fwd;     // 前递后操作数A
  logic [31:0]        operand_b_fwd;     // 前递后操作数B

  // ALU输出
  logic [31:0]        alu_result;        // ALU结果
  logic               alu_comparison;    // ALU比较结果
  logic               alu_is_equal;      // ALU相等结果

  // 分支单元输出
  logic               branch_taken;      // 分支跳转
  logic [31:0]        branch_target;     // 分支目标

  // PC+4
  logic [31:0]        pc_plus4;          // PC+4计算结果

  // ==========================================================================
  // ID/EX 流水线寄存器
  // ==========================================================================
  // TODO: 锁存ID阶段的数据
  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     ctrl_signals_q <= '0;
  //     rs1_rdata_q    <= 32'b0;
  //     rs2_rdata_q    <= 32'b0;
  //     imm_q           <= 32'b0;
  //     pc_q            <= 32'b0;
  //     rs1_addr_q      <= 5'b0;
  //     rs2_addr_q      <= 5'b0;
  //     rd_addr_q       <= 5'b0;
  //     instr_valid_q   <= 1'b0;
  //   end else if (flush_i) begin
  //     // Flush: 插入bubble
  //     ctrl_signals_q.reg_write <= 1'b0;
  //     ctrl_signals_q.mem_read  <= 1'b0;
  //     ctrl_signals_q.mem_write <= 1'b0;
  //     instr_valid_q            <= 1'b0;
  //   end else if (!stall_i) begin
  //     ctrl_signals_q <= ctrl_signals_i;
  //     rs1_rdata_q    <= rs1_rdata_i;
  //     rs2_rdata_q    <= rs2_rdata_i;
  //     imm_q           <= imm_i;
  //     pc_q            <= pc_i;
  //     rs1_addr_q      <= rs1_addr_i;
  //     rs2_addr_q      <= rs2_addr_i;
  //     rd_addr_q       <= rd_addr_i;
  //     instr_valid_q   <= instr_valid_i;
  //   end
  // end

  // ==========================================================================
  // 前递多路选择器 (forward_mux) - 条件编译
  // ==========================================================================
`ifdef RVP_FORWARDING
  // TODO: rs1前递选择
  // always_comb begin
  //   unique case (forward_a_i)
  //     FWD_NONE:    operand_a_fwd = rs1_rdata_q;
  //     FWD_EX_MEM:  operand_a_fwd = forward_a_data_i;
  //     FWD_MEM_WB:  operand_a_fwd = forward_a_data_i;
  //     FWD_WB:      operand_a_fwd = forward_a_data_i;
  //     default:     operand_a_fwd = rs1_rdata_q;
  //   endcase
  // end

  // TODO: rs2前递选择
  // always_comb begin
  //   unique case (forward_b_i)
  //     FWD_NONE:    operand_b_fwd = rs2_rdata_q;
  //     FWD_EX_MEM:  operand_b_fwd = forward_b_data_i;
  //     FWD_MEM_WB:  operand_b_fwd = forward_b_data_i;
  //     FWD_WB:      operand_b_fwd = forward_b_data_i;
  //     default:     operand_b_fwd = rs2_rdata_q;
  //   endcase
  // end
`else
  // 无前递: 直接使用寄存器值
  // TODO: assign operand_a_fwd = rs1_rdata_q;
  // TODO: assign operand_b_fwd = rs2_rdata_q;
`endif

  // ==========================================================================
  // ALU操作数选择
  // ==========================================================================

  // 操作数A: rs1值 或 PC
  // TODO: assign operand_a = ctrl_signals_q.alu_src_a ? pc_q : operand_a_fwd;

  // 操作数B: rs2值 或 立即数
  // TODO: assign operand_b = ctrl_signals_q.alu_src_b ? imm_q : operand_b_fwd;

  // ==========================================================================
  // ALU实例化
  // ==========================================================================
  rvp_alu alu_inst (
    .operand_a_i        (operand_a),
    .operand_b_i        (operand_b),
    .alu_op_i           (ctrl_signals_q.alu_op),
`ifdef RVP_RV32M
    .multdiv_ready_i    (1'b1),     // TODO: 连接乘除法器
    .multdiv_result_i   (32'b0),    // TODO: 连接乘除法器
    .multdiv_sel_i      (1'b0),     // TODO: 连接乘除法器
    .mult_en_o          (),         // TODO: 连接乘除法器
    .div_en_o           (),         // TODO: 连接乘除法器
`endif
    .result_o           (alu_result),
    .comparison_result_o(alu_comparison),
    .is_equal_result_o  (alu_is_equal)
  );

  // ==========================================================================
  // 分支单元实例化
  // ==========================================================================
  rvp_branch_unit branch_unit_inst (
    .operand_a_i    (operand_a_fwd),
    .operand_b_i    (operand_b_fwd),
    .pc_i           (pc_q),
    .imm_i          (imm_q),
    .branch_type_i  (ctrl_signals_q.branch_type),
    .is_jal_i       (ctrl_signals_q.jump & ~ctrl_signals_q.jalr),
    .is_jalr_i      (ctrl_signals_q.jalr),
    .branch_taken_o (branch_taken),
    .branch_target_o (branch_target)
  );

  // ==========================================================================
  // PC+4 计算
  // ==========================================================================
  // TODO: assign pc_plus4 = pc_q + 32'd4;

  // ==========================================================================
  // 输出赋值
  // ==========================================================================

  // ALU结果
  // TODO: assign alu_result_o       = alu_result;
  // TODO: assign alu_result_valid_o  = instr_valid_q & ~flush_i;

  // 内存接口
  // TODO: assign mem_addr_o          = alu_result;
  // TODO: assign mem_wdata_o          = operand_b_fwd;  // rs2值或前递值
  // TODO: assign mem_req_o           = (ctrl_signals_q.mem_read | ctrl_signals_q.mem_write) & instr_valid_q;
  // TODO: assign mem_we_o            = ctrl_signals_q.mem_write;
  // TODO: assign mem_size_o          = ctrl_signals_q.mem_size;

  // PC+4
  // TODO: assign pc4_o               = pc_plus4;

  // 寄存器写回
  // TODO: assign rd_addr_o          = rd_addr_q;
  // TODO: assign rf_we_o            = ctrl_signals_q.reg_write & instr_valid_q & ~flush_i;
  // TODO: assign wb_src_o           = ctrl_signals_q.wb_src;

  // 分支输出
  // TODO: assign branch_taken_o     = branch_taken & instr_valid_q;
  // TODO: assign branch_target_o    = branch_target;

  // 指令有效
  // TODO: assign instr_valid_o      = instr_valid_q;

endmodule
