/**
 * rvp_decoder.sv - RVP Instruction Decoder
 *
 * 指令译码器，纯组合逻辑。根据32位指令生成控制信号结构体。
 * 参考ibex_decoder.sv的设计。
 *
 * 功能:
 *   - 解析指令字段 (opcode, funct3, funct7, rd, rs1, rs2)
 *   - 生成ctrl_signals_t结构体 (ALU操作、内存访问、寄存器写回等)
 *   - 提取源/目标寄存器地址
 *   - 确定立即数类型
 *   - 检测非法指令
 *
 * 支持的指令集:
 *   - RV32I全部指令 (LUI, AUIPC, JAL, JALR, 分支, 加载, 存储,
 *     算术立即数, 算术寄存器, FENCE, ECALL, EBREAK)
 *   - M扩展 (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU) - 条件编译
 */

`include "rvp_config.svh"

module rvp_decoder import rvp_pkg::*; #(
    parameter bit RV32E = 1'b0   // 1=RV32E (16 regs), 0=RV32I (32 regs)
) (
    input  logic [31:0]       instr_i,         // 32位指令输入
    input  logic              illegal_c_insn_i, // 压缩指令非法标志 (C扩展)

    // 控制信号输出
    output ctrl_signals_t    ctrl_signals_o,  // 控制信号结构体
    output logic [REG_ADDR_W-1:0] rs1_addr_o,  // 源寄存器1地址
    output logic [REG_ADDR_W-1:0] rs2_addr_o,  // 源寄存器2地址
    output logic [REG_ADDR_W-1:0] rd_addr_o,   // 目标寄存器地址
    output imm_type_e         imm_type_o,      // 立即数类型

    // 异常/特殊指令标志
    output logic              illegal_insn_o,  // 非法指令标志
    output logic              ecall_insn_o,    // ECALL指令标志
    output logic              ebreak_insn_o,   // EBREAK指令标志
    output logic              mret_insn_o,     // MRET指令标志
    output logic              wfi_insn_o       // WFI指令标志
);

  import rvp_pkg::*;

  // ==========================================================================
  // 指令字段提取
  // ==========================================================================

  logic [6:0]  opcode;    // 操作码 [6:0]
  logic [4:0]  rd;        // 目标寄存器 [11:7]
  logic [2:0]  funct3;    // 功能码3 [14:12]
  logic [4:0]  rs1;       // 源寄存器1 [19:15]
  logic [4:0]  rs2;       // 源寄存器2 [24:20]
  logic [6:0]  funct7;    // 功能码7 [31:25]

  // TODO: 提取指令字段
  // assign opcode = instr_i[6:0];
  // assign rd     = instr_i[11:7];
  // assign funct3 = instr_i[14:12];
  // assign rs1    = instr_i[19:15];
  // assign rs2    = instr_i[24:20];
  // assign funct7 = instr_i[31:25];

  // ==========================================================================
  // 内部信号
  // ==========================================================================

  logic        illegal_insn;     // 非法指令内部信号
  logic        illegal_reg_rv32e; // RV32E寄存器地址非法

  // RV32E检查: 寄存器地址>=16为非法
  // TODO: assign illegal_reg_rv32e = RV32E &
  //          ((rs1 >= 16) | (rs2 >= 16) | (rd >= 16));

  // ==========================================================================
  // 寄存器地址输出
  // ==========================================================================

  // TODO: assign rs1_addr_o = rs1;
  // TODO: assign rs2_addr_o = rs2;
  // TODO: assign rd_addr_o  = rd;

  // ==========================================================================
  // 译码主逻辑
  // ==========================================================================
  always_comb begin
    // 默认值: 所有控制信号清零
    ctrl_signals_o = '{
      alu_src_a:    1'b0,
      alu_src_b:    1'b0,
      mem_read:     1'b0,
      mem_write:    1'b0,
      reg_write:    1'b0,
      branch:       1'b0,
      jump:         1'b0,
      jalr:         1'b0,
      wb_src:       WB_ALU,
      alu_op:       ALU_NOP,
      branch_type:  BRANCH_NONE,
      mem_size:     MEM_NONE,
      imm_type:     IMM_NONE,
      m_extension:  1'b0
    };

    illegal_insn   = 1'b0;
    ecall_insn_o   = 1'b0;
    ebreak_insn_o  = 1'b0;
    mret_insn_o    = 1'b0;
    wfi_insn_o     = 1'b0;
    imm_type_o     = IMM_NONE;

    // TODO: 根据opcode进行译码
    // unique case (opcode)
    //   // ============================================================
    //   // LUI: Load Upper Immediate
    //   // ============================================================
    //   OPCODE_LUI: begin
    //     ctrl_signals_o.reg_write = 1'b1;
    //     ctrl_signals_o.alu_op    = ALU_LUI;
    //     ctrl_signals_o.alu_src_b = 1'b1;  // 使用立即数
    //     ctrl_signals_o.wb_src    = WB_ALU;
    //     imm_type_o               = IMM_U;
    //   end
    //
    //   // ============================================================
    //   // AUIPC: Add Upper Immediate to PC
    //   // ============================================================
    //   OPCODE_AUIPC: begin
    //     ctrl_signals_o.reg_write = 1'b1;
    //     ctrl_signals_o.alu_op    = ALU_ADD;
    //     ctrl_signals_o.alu_src_a = 1'b1;  // 使用PC
    //     ctrl_signals_o.alu_src_b = 1'b1;  // 使用立即数
    //     ctrl_signals_o.wb_src    = WB_ALU;
    //     imm_type_o               = IMM_U;
    //   end
    //
    //   // ============================================================
    //   // JAL: Jump and Link
    //   // ============================================================
    //   OPCODE_JAL: begin
    //     ctrl_signals_o.reg_write = 1'b1;
    //     ctrl_signals_o.jump       = 1'b1;
    //     ctrl_signals_o.wb_src    = WB_PC4;
    //     imm_type_o               = IMM_J;
    //   end
    //
    //   // ============================================================
    //   // JALR: Jump and Link Register
    //   // ============================================================
    //   OPCODE_JALR: begin
    //     ctrl_signals_o.reg_write = 1'b1;
    //     ctrl_signals_o.jump       = 1'b1;
    //     ctrl_signals_o.jalr       = 1'b1;
    //     ctrl_signals_o.wb_src    = WB_PC4;
    //     imm_type_o               = IMM_I;
    //   end
    //
    //   // ============================================================
    //   // BRANCH: 条件分支
    //   // ============================================================
    //   OPCODE_BRANCH: begin
    //     ctrl_signals_o.branch = 1'b1;
    //     imm_type_o           = IMM_B;
    //     // TODO: 根据funct3设置branch_type
    //     // case (funct3)
    //     //   3'b000: ctrl_signals_o.branch_type = BRANCH_BEQ;
    //     //   3'b001: ctrl_signals_o.branch_type = BRANCH_BNE;
    //     //   3'b100: ctrl_signals_o.branch_type = BRANCH_BLT;
    //     //   3'b101: ctrl_signals_o.branch_type = BRANCH_BGE;
    //     //   3'b110: ctrl_signals_o.branch_type = BRANCH_BLTU;
    //     //   3'b111: ctrl_signals_o.branch_type = BRANCH_BGEU;
    //     //   default: illegal_insn = 1'b1;
    //     // endcase
    //   end
    //
    //   // ============================================================
    //   // LOAD: 加载指令
    //   // ============================================================
    //   OPCODE_LOAD: begin
    //     ctrl_signals_o.reg_write = 1'b1;
    //     ctrl_signals_o.mem_read  = 1'b1;
    //     ctrl_signals_o.alu_op   = ALU_ADD;
    //     ctrl_signals_o.alu_src_b = 1'b1;
    //     ctrl_signals_o.wb_src   = WB_MEM;
    //     imm_type_o               = IMM_I;
    //     // TODO: 根据funct3设置mem_size
    //     // case (funct3)
    //     //   3'b000: ctrl_signals_o.mem_size = MEM_B;
    //     //   3'b001: ctrl_signals_o.mem_size = MEM_H;
    //     //   3'b010: ctrl_signals_o.mem_size = MEM_W;
    //     //   3'b100: ctrl_signals_o.mem_size = MEM_BU;
    //     //   3'b101: ctrl_signals_o.mem_size = MEM_HU;
    //     //   default: illegal_insn = 1'b1;
    //     // endcase
    //   end
    //
    //   // ============================================================
    //   // STORE: 存储指令
    //   // ============================================================
    //   OPCODE_STORE: begin
    //     ctrl_signals_o.mem_write = 1'b1;
    //     ctrl_signals_o.alu_op   = ALU_ADD;
    //     ctrl_signals_o.alu_src_b = 1'b1;
    //     imm_type_o               = IMM_S;
    //     // TODO: 根据funct3设置mem_size
    //     // case (funct3)
    //     //   3'b000: ctrl_signals_o.mem_size = MEM_B;
    //     //   3'b001: ctrl_signals_o.mem_size = MEM_H;
    //     //   3'b010: ctrl_signals_o.mem_size = MEM_W;
    //     //   default: illegal_insn = 1'b1;
    //     // endcase
    //   end
    //
    //   // ============================================================
    //   // OP-IMM: 算术立即数指令
    //   // ============================================================
    //   OPCODE_OP_IMM: begin
    //     ctrl_signals_o.reg_write = 1'b1;
    //     ctrl_signals_o.alu_src_b = 1'b1;
    //     imm_type_o               = IMM_I;
    //     // TODO: 根据funct3设置alu_op
    //     // case (funct3)
    //     //   3'b000: ctrl_signals_o.alu_op = ALU_ADD;   // ADDI
    //     //   3'b010: ctrl_signals_o.alu_op = ALU_SLT;  // SLTI
    //     //   3'b011: ctrl_signals_o.alu_op = ALU_SLTU; // SLTIU
    //     //   3'b100: ctrl_signals_o.alu_op = ALU_XOR;   // XORI
    //     //   3'b110: ctrl_signals_o.alu_op = ALU_OR;    // ORI
    //     //   3'b111: ctrl_signals_o.alu_op = ALU_AND;   // ANDI
    //     //   3'b001: ctrl_signals_o.alu_op = ALU_SLL;   // SLLI
    //     //   3'b101: begin
    //     //     if (funct7[5]) ctrl_signals_o.alu_op = ALU_SRA; // SRAI
    //     //     else           ctrl_signals_o.alu_op = ALU_SRL; // SRLI
    //     //   end
    //     //   default: illegal_insn = 1'b1;
    //     // endcase
    //   end
    //
    //   // ============================================================
    //   // OP: 算术寄存器指令
    //   // ============================================================
    //   OPCODE_OP: begin
    //     ctrl_signals_o.reg_write = 1'b1;
    //     // TODO: 根据funct3/funct7设置alu_op
    //     // case (funct3)
    //     //   3'b000: begin
    //     //     if (funct7[5]) ctrl_signals_o.alu_op = ALU_SUB; // SUB
    //     //     else           ctrl_signals_o.alu_op = ALU_ADD; // ADD
    //     //   end
    //     //   3'b001: ctrl_signals_o.alu_op = ALU_SLL;  // SLL
    //     //   3'b010: ctrl_signals_o.alu_op = ALU_SLT;  // SLT
    //     //   3'b011: ctrl_signals_o.alu_op = ALU_SLTU; // SLTU
    //     //   3'b100: ctrl_signals_o.alu_op = ALU_XOR;  // XOR
    //     //   3'b101: begin
    //     //     if (funct7[5]) ctrl_signals_o.alu_op = ALU_SRA; // SRA
    //     //     else           ctrl_signals_o.alu_op = ALU_SRL; // SRL
    //     //   end
    //     //   3'b110: ctrl_signals_o.alu_op = ALU_OR;   // OR
    //     //   3'b111: ctrl_signals_o.alu_op = ALU_AND;  // AND
    //     //   default: illegal_insn = 1'b1;
    //     // endcase
    //
    //     // M扩展条件编译
    // `ifdef RVP_RV32M
    //     // TODO: M扩展指令译码
    //     // if (funct7 == 7'b0000001) begin
    //     //   ctrl_signals_o.m_extension = 1'b1;
    //     //   case (funct3)
    //     //     3'b000: ctrl_signals_o.alu_op = ALU_MUL;   // MUL
    //     //     3'b001: ctrl_signals_o.alu_op = ALU_MULH;  // MULH
    //     //     3'b010: ctrl_signals_o.alu_op = ALU_MULH;  // MULHSU
    //     //     3'b011: ctrl_signals_o.alu_op = ALU_MULH;  // MULHU
    //     //     3'b100: ctrl_signals_o.alu_op = ALU_DIV;   // DIV
    //     //     3'b101: ctrl_signals_o.alu_op = ALU_DIV;   // DIVU
    //     //     3'b110: ctrl_signals_o.alu_op = ALU_REM;   // REM
    //     //     3'b111: ctrl_signals_o.alu_op = ALU_REM;   // REMU
    //     //     default: illegal_insn = 1'b1;
    //     //   endcase
    //     // end
    // `endif
    //   end
    //
    //   // ============================================================
    //   // MISC-MEM: FENCE (作为NOP处理)
    //   // ============================================================
    //   OPCODE_MISC: begin
    //     // FENCE作为NOP处理
    //     ctrl_signals_o.alu_op = ALU_NOP;
    //   end
    //
    //   // ============================================================
    //   // SYSTEM: ECALL, EBREAK, MRET, WFI, CSR
    //   // ============================================================
    //   OPCODE_SYSTEM: begin
    //     // TODO: 根据funct3和instr[31:20]解析系统指令
    //     // case (funct3)
    //     //   3'b000: begin
    //     //     case (instr_i[31:20])
    //     //       20'h000: ecall_insn_o  = 1'b1;  // ECALL
    //     //       20'h001: ebreak_insn_o = 1'b1;  // EBREAK
    //     //       20'h302: mret_insn_o   = 1'b1;  // MRET
    //     //       20'h105: wfi_insn_o    = 1'b1;  // WFI
    //     //       default: illegal_insn  = 1'b1;
    //     //     endcase
    //     //   end
    //     //   default: begin
    //     //     // CSR指令处理
    //     //     // TODO: 解析CSRRW, CSRRS, CSRRC等
    //     //     illegal_insn = 1'b1;
    //     //   end
    //     // endcase
    //   end
    //
    //   default: begin
    //     illegal_insn = 1'b1;
    //   end
    // endcase

    // 合并非法指令标志
    // TODO: illegal_insn = illegal_insn | illegal_c_insn_i | illegal_reg_rv32e;
  end

  // ==========================================================================
  // 输出赋值
  // ==========================================================================

  // TODO: assign illegal_insn_o = illegal_insn;
  // TODO: ctrl_signals_o.imm_type已包含在结构体中

endmodule
