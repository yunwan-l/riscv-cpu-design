// =============================================================================
// rvp_core_single.sv — RVP 单周期 CPU 核心
// =============================================================================
// 这是整个项目的"组装"环节：把前面造的所有零件用线连起来，形成完整的数据通路。
//
// 数据流（一个时钟周期内完成）：
//   PC → 指令存储器 → 指令
//   指令 → 译码器 → 控制信号
//   指令 → 立即数生成器 → 立即数
//   控制信号 + 寄存器地址 → 寄存器堆 → rs1_data, rs2_data
//   rs1_data/PC → MUX → ALU 操作数 A
//   rs2_data/立即数 → MUX → ALU 操作数 B
//   ALU → 运算结果 + 比较结果
//   比较结果 + 分支标志 → 分支单元 → branch_taken
//   ALU 结果 → 数据存储器地址；rs2_data → 写数据
//   数据存储器 → 读出数据
//   写回 MUX：ALU结果/内存数据/PC+4/立即数 → 寄存器堆写回
//   PC 逻辑：PC+4/分支目标/跳转目标/JALR目标 → 下一条 PC
// =============================================================================

module rvp_core_single (
  input  logic clk_i,
  input  logic rst_ni,

  // 调试接口（仿真用，FPGA 上可去掉）
  output logic [31:0] pc_o,         // 当前 PC（观察执行进度）
  output logic [31:0] instr_o,      // 当前指令
  output logic        illegal_o     // 非法指令标志
);

  import rvp_pkg::*;

  // =========================================================================
  // 内部信号声明
  // =========================================================================
  logic [31:0] pc, pc_next;

  // 取指
  logic [31:0] instr;

  // 译码
  ctrl_t       ctrl;

  // 立即数
  logic [31:0] imm;

  // 寄存器堆
  logic [31:0] rs1_data, rs2_data;

  // ALU
  alu_op_e     alu_op;
  logic [31:0] alu_op_a, alu_op_b;
  logic [31:0] alu_result;
  logic        alu_cmp;

  // 乘除法单元
  logic [31:0] multdiv_result;
  logic [31:0] ex_result;       // ALU 或 multdiv 的结果（二选一）

  // 分支
  logic        branch_taken;

  // 数据存储器
  logic [31:0] mem_rdata;

  // 写回
  logic [31:0] wb_data;

  // =========================================================================
  // 1. PC 寄存器
  // =========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) pc <= 32'h0;
    else         pc <= pc_next;
  end

  // =========================================================================
  // 2. 取指：PC → 指令存储器 → 指令
  // =========================================================================
  rvp_instr_mem instr_mem (
    .addr_i  (pc),
    .instr_o (instr)
  );

  // =========================================================================
  // 3. 译码：指令 → 控制信号
  // =========================================================================
  rvp_decoder decoder (
    .instr_i (instr),
    .ctrl_o  (ctrl)
  );

  // =========================================================================
  // 4. 立即数生成：指令 → 立即数
  // =========================================================================
  rvp_imm_generator imm_gen (
    .instr_i    (instr),
    .imm_type_i (ctrl.imm_type),
    .imm_o      (imm)
  );

  // =========================================================================
  // 5. 读寄存器堆
  // =========================================================================
  rvp_register_file reg_file (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .we_i     (ctrl.reg_write),
    .waddr_i  (ctrl.rd_addr),
    .wdata_i  (wb_data),
    .raddr1_i (ctrl.rs1_addr),
    .rdata1_o (rs1_data),
    .raddr2_i (ctrl.rs2_addr),
    .rdata2_o (rs2_data)
  );

  // =========================================================================
  // 6. ALU 操作数选择
  // =========================================================================
  // operand A: rs1_data 或 PC（auipc 用）
  assign alu_op_a = ctrl.alu_op_a_sel ? pc : rs1_data;

  // operand B: rs2_data 或 立即数
  assign alu_op_b = ctrl.alu_op_b_sel ? imm : rs2_data;

  // =========================================================================
  // 7. ALU 运算
  // =========================================================================
  rvp_alu alu (
    .alu_op_i     (ctrl.alu_op),
    .operand_a_i  (alu_op_a),
    .operand_b_i  (alu_op_b),
    .result_o     (alu_result),
    .cmp_result_o (alu_cmp)
  );

  // =========================================================================
  // 7b. 乘除法单元（M 扩展）
  // =========================================================================
  rvp_multdiv multdiv (
    .op_i       (ctrl.multdiv_op),
    .operand_a_i(rs1_data),
    .operand_b_i(rs2_data),
    .result_o   (multdiv_result)
  );

  // 结果选择：M 扩展指令用 multdiv 结果，其余用 ALU 结果
  assign ex_result = ctrl.use_multdiv ? multdiv_result : alu_result;

  // =========================================================================
  // 8. 分支判定
  // =========================================================================
  rvp_branch_unit branch_unit (
    .is_branch_i   (ctrl.branch),
    .cmp_result_i  (alu_cmp),
    .branch_taken_o(branch_taken)
  );

  // =========================================================================
  // 9. 数据存储器访问
  // =========================================================================
  rvp_data_mem data_mem (
    .clk_i         (clk_i),
    .addr_i        (alu_result),
    .write_data_i  (rs2_data),
    .mem_read_i    (ctrl.mem_read),
    .mem_write_i   (ctrl.mem_write),
    .mem_size_i    (ctrl.mem_size),
    .mem_unsigned_i(ctrl.mem_unsigned),
    .read_data_o   (mem_rdata)
  );

  // =========================================================================
  // 10. 写回选择
  // =========================================================================
  always_comb begin
    unique case (ctrl.wb_sel)
      WB_ALU: wb_data = ex_result;    // 大多数指令（含 M 扩展）
      WB_MEM: wb_data = mem_rdata;    // load 指令
      WB_PC4: wb_data = pc + 32'd4;   // jal/jalr（返回地址）
      WB_IMM: wb_data = imm;          // lui
      default: wb_data = 32'b0;
    endcase
  end

  // =========================================================================
  // 11. 下一条 PC 选择
  // =========================================================================
  always_comb begin
    unique case (ctrl.next_pc)
      PC_SEQ:    pc_next = pc + 32'd4;                    // 顺序执行
      PC_BRANCH: pc_next = branch_taken ? (pc + imm)      // 分支跳转
                                        : (pc + 32'd4);   // 分支不跳
      PC_JUMP:   pc_next = pc + imm;                       // JAL
      PC_JALR:   pc_next = (rs1_data + imm) & ~32'b1;      // JALR（末位清零）
      default:   pc_next = pc + 32'd4;
    endcase
  end

  // =========================================================================
  // 调试输出
  // =========================================================================
  assign pc_o      = pc;
  assign instr_o   = instr;
  assign illegal_o = ctrl.illegal;

endmodule : rvp_core_single
