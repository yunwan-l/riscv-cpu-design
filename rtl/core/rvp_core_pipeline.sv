// =============================================================================
// rvp_core_pipeline.sv — RVP 5 级流水线 CPU 核心
// =============================================================================
// 这是单周期 CPU 的流水线版本。5 级：IF → ID → EX → MEM → WB
//
// 相比单周期，新增了：
//   1. 4 组流水线寄存器（rvp_pipeline_regs）
//   2. 前递单元（rvp_forward_unit）— 解决数据冒险
//   3. 冒险检测单元（rvp_hazard_unit）— 解决 Load-Use 冒险
//   4. 冲刷逻辑 — 分支/跳转时清掉错误进入的指令
//
// 冲刷策略（简化版）：
//   分支/跳转在 EX 级判定。如果跳转，IF/ID 和 ID/EX 都冲刷（清掉2条错误指令）。
//   这会造成 2 周期惩罚，但对教学流水线足够。
//   （更高级的做法是分支预测，在 ID 级就判定，这里暂不实现）
// =============================================================================

module rvp_core_pipeline (
  input  logic clk_i,
  input  logic rst_ni,

  // 调试接口
  output logic [31:0] pc_o,
  output logic [31:0] instr_o,
  output logic        illegal_o,

  // 数据总线接口（SoC 用）
  // CPU 作为总线主设备，通过这些端口访问外部 RAM / UART / GPIO / Timer
  output logic [31:0]             dbus_addr_o,      // 访存地址（字节地址）
  output logic                    dbus_read_o,       // 读使能
  output logic                    dbus_write_o,      // 写使能
  output rvp_pkg::mem_size_e      dbus_size_o,       // 访问大小 B/H/W
  output logic                    dbus_unsigned_o,   // 无符号读
  output logic [31:0]             dbus_wdata_o,      // 写数据
  input  logic [31:0]             dbus_rdata_i       // 读返回数据
);

  import rvp_pkg::*;

  // =========================================================================
  // 流水线级间信号
  // =========================================================================
  // IF 级
  logic [31:0] if_pc, if_pc_next, if_instr;

  // IF/ID 级间
  logic [31:0] id_pc, id_instr;

  // ID 级
  ctrl_t       id_ctrl;
  logic [31:0] id_imm;
  logic [31:0] id_rs1_data, id_rs2_data;
  logic [31:0] id_rs1_fwd, id_rs2_fwd;  // WB→ID 前递后的值

  // ID/EX 级间
  logic [31:0] ex_pc;
  ctrl_t       ex_ctrl;
  logic [31:0] ex_rs1_data, ex_rs2_data, ex_imm;

  // EX 级
  logic [1:0]  forward_a, forward_b;
  logic [31:0] ex_alu_op_a, ex_alu_op_b;
  logic [31:0] ex_alu_result;
  logic        ex_alu_cmp;  // 1-bit: ALU 比较结果（分支条件是否成立）
  logic [31:0] ex_forward_a_val, ex_forward_b_val;
  logic [31:0] ex_multdiv_result;    // M 扩展乘除法结果
  logic [31:0] ex_result;            // ALU 或 multdiv 结果（二选一）

  // EX/MEM 级间
  logic [31:0] mem_pc;
  ctrl_t       mem_ctrl;
  logic [31:0] mem_alu_result, mem_rs2_data, mem_imm;

  // MEM 级
  logic [31:0] mem_rdata;
  logic [31:0] mem_imm_wb;   // lui 的 imm 传到 WB 级
  logic [31:0] mem_wb_data;  // MEM 级最终写回值（用于 EX/MEM 前递）

  // MEM/WB 级间
  logic [31:0] wb_pc;
  ctrl_t       wb_ctrl;
  logic [31:0] wb_alu_result, wb_rdata;
  logic [31:0] wb_imm;        // lui 的 imm

  // WB 级
  logic [31:0] wb_data;

  // =========================================================================
  // 控制信号
  // =========================================================================
  logic stall;            // Load-Use 停顿
  logic branch_taken;     // 分支跳转
  logic flush_if_id;      // 冲刷 IF/ID
  logic flush_id_ex;      // 冲刷 ID/EX
  logic take_jump;        // 跳转指令（jal/jalr）需要冲刷

  // =========================================================================
  // 1. IF 级：取指
  // =========================================================================
  // PC 寄存器
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      if_pc <= 32'h0;
    else if (stall)
      if_pc <= if_pc;        // 停顿：PC 保持
    else
      if_pc <= if_pc_next;   // 正常更新
  end

  // 指令存储器（DEPTH=2048 → ADDR_BITS=11 → 11位字地址）
  rvp_instr_mem instr_mem (
    .addr_i  (if_pc[12:2]),
    .instr_o (if_instr)
  );

  // =========================================================================
  // 2. IF/ID 寄存器
  // =========================================================================
  rvp_pipeline_regs pipe_regs (
    .clk_i(clk_i), .rst_ni(rst_ni),

    // IF/ID
    .if_id_flush_i (flush_if_id),
    .if_id_stall_i (stall),
    .if_pc_i       (if_pc),
    .if_instr_i    (if_instr),
    .id_pc_o       (id_pc),
    .id_instr_o    (id_instr),

    // ID/EX
    .id_ex_flush_i (flush_id_ex),
    .id_ex_stall_i (stall),
    .id_pc_i       (id_pc),
    .id_ctrl_i     (id_ctrl),
    .id_rs1_data_i (id_rs1_fwd),
    .id_rs2_data_i (id_rs2_fwd),
    .id_imm_i      (id_imm),
    .ex_pc_o       (ex_pc),
    .ex_ctrl_o     (ex_ctrl),
    .ex_rs1_data_o (ex_rs1_data),
    .ex_rs2_data_o (ex_rs2_data),
    .ex_imm_o      (ex_imm),

    // EX/MEM
    .ex_mem_flush_i (1'b0),
    .ex_mem_stall_i (1'b0),
    .ex_pc_i        (ex_pc),
    .ex_ctrl_i      (ex_ctrl),
    .ex_alu_result_i(ex_result),       // ALU 或 multdiv 结果
    .ex_rs2_data_i  (ex_forward_b_val),  // store 用前递后的值
    .ex_imm_i       (ex_imm),
    .mem_pc_o       (mem_pc),
    .mem_ctrl_o     (mem_ctrl),
    .mem_alu_result_o(mem_alu_result),
    .mem_rs2_data_o (mem_rs2_data),
    .mem_imm_o      (mem_imm),

    // MEM/WB
    .mem_wb_flush_i (1'b0),
    .mem_wb_stall_i (1'b0),
    .mem_pc_i       (mem_pc),
    .mem_ctrl_i     (mem_ctrl),
    .mem_alu_result_i(mem_alu_result),
    .mem_rdata_i    (mem_rdata),
    .wb_pc_o        (wb_pc),
    .wb_ctrl_o      (wb_ctrl),
    .wb_alu_result_o(wb_alu_result),
    .wb_rdata_o     (wb_rdata)
  );

  // =========================================================================
  // 3. ID 级：译码 + 读寄存器 + 立即数生成
  // =========================================================================
  rvp_decoder decoder (
    .instr_i (id_instr),
    .ctrl_o  (id_ctrl)
  );

  rvp_imm_generator imm_gen (
    .instr_i    (id_instr),
    .imm_type_i (id_ctrl.imm_type),
    .imm_o      (id_imm)
  );

  rvp_register_file reg_file (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .we_i     (wb_ctrl.reg_write),
    .waddr_i  (wb_ctrl.rd_addr),
    .wdata_i  (wb_data),
    .raddr1_i (id_ctrl.rs1_addr),
    .rdata1_o (id_rs1_data),
    .raddr2_i (id_ctrl.rs2_addr),
    .rdata2_o (id_rs2_data)
  );

  // -------------------------------------------------------------------------
  // WB→ID 前递（替代寄存器堆 write-first）
  // -------------------------------------------------------------------------
  // 问题：寄存器堆同步写 + 异步读。当 WB 级写 rd 的同时 ID 级读同一个寄存器，
  //       ID 读到的是旧值（写沿还没到），导致后一条指令用了过期数据。
  // 解决：如果 WB 级正在写 rd，且 rd == ID 级要读的 rs1/rs2，直接用 wb_data。
  //       这和 EX 级前递原理一样，只是发生在更早的 ID 级。
  // 注意：rd==x0 时不前递（x0 永远为 0）。
  assign id_rs1_fwd = (wb_ctrl.reg_write && (wb_ctrl.rd_addr != 5'd0) &&
                       (wb_ctrl.rd_addr == id_ctrl.rs1_addr)) ? wb_data : id_rs1_data;
  assign id_rs2_fwd = (wb_ctrl.reg_write && (wb_ctrl.rd_addr != 5'd0) &&
                       (wb_ctrl.rd_addr == id_ctrl.rs2_addr)) ? wb_data : id_rs2_data;

  // =========================================================================
  // 4. EX 级：ALU 运算 + 前递
  // =========================================================================
  // 前递单元
  rvp_forward_unit forward_unit (
    .ex_rs1_addr_i  (ex_ctrl.rs1_addr),
    .ex_rs2_addr_i  (ex_ctrl.rs2_addr),
    .mem_rd_addr_i  (mem_ctrl.rd_addr),
    .mem_reg_write_i(mem_ctrl.reg_write),
    .wb_rd_addr_i   (wb_ctrl.rd_addr),
    .wb_reg_write_i (wb_ctrl.reg_write),
    .forward_a_o    (forward_a),
    .forward_b_o    (forward_b)
  );

  // 前递多路选择
  always_comb begin
    unique case (forward_a)
      2'b00:   ex_forward_a_val = ex_rs1_data;
      2'b01:   ex_forward_a_val = wb_data;          // MEM/WB 前递
      2'b10:   ex_forward_a_val = mem_wb_data;      // EX/MEM 前递（用正确写回值）
      default: ex_forward_a_val = ex_rs1_data;
    endcase

    unique case (forward_b)
      2'b00:   ex_forward_b_val = ex_rs2_data;
      2'b01:   ex_forward_b_val = wb_data;
      2'b10:   ex_forward_b_val = mem_wb_data;      // EX/MEM 前递（用正确写回值）
      default: ex_forward_b_val = ex_rs2_data;
    endcase
  end

  // ALU 操作数选择
  assign ex_alu_op_a = ex_ctrl.alu_op_a_sel ? ex_pc : ex_forward_a_val;
  assign ex_alu_op_b = ex_ctrl.alu_op_b_sel ? ex_imm : ex_forward_b_val;

  // ALU
  rvp_alu alu (
    .alu_op_i     (ex_ctrl.alu_op),
    .operand_a_i  (ex_alu_op_a),
    .operand_b_i  (ex_alu_op_b),
    .result_o     (ex_alu_result),
    .cmp_result_o (ex_alu_cmp)
  );

  // 乘除法单元（M 扩展）— 操作数用前递后的值
  rvp_multdiv multdiv (
    .op_i       (ex_ctrl.multdiv_op),
    .operand_a_i(ex_forward_a_val),
    .operand_b_i(ex_forward_b_val),
    .result_o   (ex_multdiv_result)
  );

  // 结果选择：M 扩展指令用 multdiv 结果，其余用 ALU 结果
  assign ex_result = ex_ctrl.use_multdiv ? ex_multdiv_result : ex_alu_result;

  // =========================================================================
  // 5. MEM 级：数据总线接口（原 data_mem 移到 SoC 顶层）
  // =========================================================================
  // CPU 不再直接例化 data_mem，而是通过总线端口对外访问。
  // SoC 顶层会把这些端口连到总线互连，再分发到 RAM / UART / GPIO / Timer。
  assign dbus_addr_o      = mem_alu_result;
  assign dbus_wdata_o     = mem_rs2_data;
  assign dbus_read_o      = mem_ctrl.mem_read;
  assign dbus_write_o     = mem_ctrl.mem_write;
  assign dbus_size_o      = mem_ctrl.mem_size;
  assign dbus_unsigned_o  = mem_ctrl.mem_unsigned;
  assign mem_rdata        = dbus_rdata_i;

  // -------------------------------------------------------------------------
  // 计算 MEM 级指令的最终写回值（用于 EX/MEM 前递）
  // 修复 bug：原来前递直接用 mem_alu_result，对 lui（wb_sel=WB_IMM）会前递 0
  //          因为 lui 的 ALU 计算 0+0=0（alu_op_b_sel 默认用 rs2=x0）
  //          现在根据 wb_sel 计算正确的写回值，与 WB 级逻辑一致
  // -------------------------------------------------------------------------
  always_comb begin
    unique case (mem_ctrl.wb_sel)
      WB_ALU: mem_wb_data = mem_alu_result;
      WB_MEM: mem_wb_data = mem_rdata;
      WB_PC4: mem_wb_data = mem_pc + 32'd4;
      WB_IMM: mem_wb_data = mem_imm;
      default: mem_wb_data = mem_alu_result;
    endcase
  end

  // =========================================================================
  // 6. WB 级：写回选择
  // =========================================================================
  // lui 的 imm 需要从 EX 传到 WB，用一个简单寄存器链
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mem_imm_wb <= 32'b0;
      wb_imm     <= 32'b0;
    end else begin
      mem_imm_wb <= ex_imm;       // EX → MEM
      wb_imm     <= mem_imm_wb;   // MEM → WB
    end
  end

  always_comb begin
    unique case (wb_ctrl.wb_sel)
      WB_ALU: wb_data = wb_alu_result;
      WB_MEM: wb_data = wb_rdata;
      WB_PC4: wb_data = wb_pc + 32'd4;
      WB_IMM: wb_data = wb_imm;   // lui
      default: wb_data = 32'b0;
    endcase
  end

  // =========================================================================
  // 7. 冒险检测：Load-Use 停顿
  // =========================================================================
  rvp_hazard_unit hazard_unit (
    .id_ex_mem_read_i(ex_ctrl.mem_read),
    .id_ex_rd_addr_i (ex_ctrl.rd_addr),
    .if_id_rs1_addr_i(id_ctrl.rs1_addr),
    .if_id_rs2_addr_i(id_ctrl.rs2_addr),
    .stall_o         (stall)
  );

  // =========================================================================
  // 8. 分支判定（在 EX 级）
  // =========================================================================
  rvp_branch_unit branch_unit (
    .is_branch_i   (ex_ctrl.branch),
    .cmp_result_i  (ex_alu_cmp),
    .branch_taken_o(branch_taken)
  );

  // 跳转指令也需要冲刷（jal/jalr 在 EX 级才确定目标）
  // ex_ctrl.next_pc != PC_SEQ 且不是分支时，就是跳转
  // 分支跳转：branch_taken=1；跳转：next_pc=PC_JUMP 或 PC_JALR
  assign take_jump = (ex_ctrl.next_pc == PC_JUMP) || (ex_ctrl.next_pc == PC_JALR);

  // =========================================================================
  // 9. 冲刷控制
  // =========================================================================
  // 分支跳转或无条件跳转时，IF/ID 和 ID/EX 的指令是错误的，需要冲刷
  assign flush_if_id = (branch_taken || take_jump) && !stall;
  assign flush_id_ex = stall;  // 停顿时 ID/EX 插入 NOP（气泡）

  // =========================================================================
  // 10. 下一条 PC 选择
  // =========================================================================
  always_comb begin
    if (stall) begin
      if_pc_next = if_pc;   // 停顿：PC 不变
    end else begin
      unique case (ex_ctrl.next_pc)
        PC_SEQ:    if_pc_next = if_pc + 32'd4;
        PC_BRANCH: if_pc_next = branch_taken ? (ex_pc + ex_imm) : (if_pc + 32'd4);
        PC_JUMP:   if_pc_next = ex_pc + ex_imm;
        PC_JALR:   if_pc_next = (ex_forward_a_val + ex_imm) & ~32'b1;
        default:   if_pc_next = if_pc + 32'd4;
      endcase
    end
  end

  // =========================================================================
  // 调试输出
  // =========================================================================
  assign pc_o      = if_pc;
  assign instr_o   = if_instr;
  assign illegal_o = id_ctrl.illegal;

endmodule : rvp_core_pipeline
