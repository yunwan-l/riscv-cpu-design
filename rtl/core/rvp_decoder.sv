// =============================================================================
// rvp_decoder.sv — RVP 指令译码器
// =============================================================================
// 功能：把 32 位 RISC-V 指令翻译成 ctrl_t 控制信号结构体，送给数据通路。
//
// 接口：
//   instr_i  : 32 位原始指令
//   ctrl_o   : 译码后的控制信号（见 rvp_pkg::ctrl_t）
//
// 译码策略：两级 case
//   第一级：按 opcode[6:0] 分成大类（LUI/AUIPC/JAL/.../OP-IMM/OP/...）
//   第二级：在需要时按 funct3[14:12] / funct7[31:25] 细分具体指令
//
// 覆盖范围：RV32I 基础整数指令集（37 条指令）
//   未识别的编码 → illegal=1（CPU 可据此触发异常，目前先标记不处理）
// =============================================================================

module rvp_decoder (
  input  logic [31:0]    instr_i,
  output rvp_pkg::ctrl_t ctrl_o
);

  import rvp_pkg::*;

  // 指令字段提取
  logic [6:0]  opcode;
  logic [4:0]  rd, rs1, rs2;
  logic [2:0]  funct3;
  logic [6:0]  funct7;
  assign opcode = instr_i[6:0];
  assign rd     = instr_i[11:7];
  assign rs1    = instr_i[19:15];
  assign rs2    = instr_i[24:20];
  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];

  // 中间变量
  ctrl_t ctrl;

  always_comb begin
    // 初始化为全零且非法
    ctrl = ctrl_zero();

    // 填入寄存器地址（所有指令都用同样位置，先统一填）
    ctrl.rs1_addr = rs1;
    ctrl.rs2_addr = rs2;
    ctrl.rd_addr  = rd;

    // -----------------------------------------------------------------------
    // 主译码：按 opcode 分大类
    // -----------------------------------------------------------------------
    unique case (opcode)

      // =====================================================================
      // LUI: U 型，把 imm[31:12] 写入 rd，不经过 ALU
      // =====================================================================
      7'b0110111: begin
        ctrl.imm_type  = IMM_U;
        ctrl.reg_write = 1'b1;
        ctrl.wb_sel    = WB_IMM;
        ctrl.illegal   = 1'b0;
      end

      // =====================================================================
      // AUIPC: U 型，rd = PC + imm[31:12]，ALU 算 PC+imm
      // =====================================================================
      7'b0010111: begin
        ctrl.imm_type     = IMM_U;
        ctrl.alu_op       = ALU_ADD;
        ctrl.alu_op_a_sel = 1'b1;   // operand A = PC
        ctrl.alu_op_b_sel = 1'b1;   // operand B = imm
        ctrl.reg_write    = 1'b1;
        ctrl.wb_sel       = WB_ALU;
        ctrl.illegal      = 1'b0;
      end

      // =====================================================================
      // JAL: J 型，rd = PC+4，PC = PC + J-imm
      // =====================================================================
      7'b1101111: begin
        ctrl.imm_type  = IMM_J;
        ctrl.reg_write = 1'b1;
        ctrl.wb_sel    = WB_PC4;
        ctrl.next_pc   = PC_JUMP;
        ctrl.illegal   = 1'b0;
      end

      // =====================================================================
      // JALR: I 型，rd = PC+4，PC = rs1 + I-imm（末位清零）
      // =====================================================================
      7'b1100111: begin
        ctrl.imm_type     = IMM_I;
        ctrl.alu_op       = ALU_ADD;
        ctrl.alu_op_b_sel = 1'b1;   // operand B = imm（地址计算用，但跳转逻辑单独处理）
        ctrl.reg_write    = 1'b1;
        ctrl.wb_sel       = WB_PC4;
        ctrl.next_pc      = PC_JALR;
        ctrl.illegal      = 1'b0;
      end

      // =====================================================================
      // BRANCH: B 型，条件成立则 PC = PC + B-imm
      // funct3 决定比较方式
      // =====================================================================
      7'b1100011: begin
        ctrl.imm_type = IMM_B;
        ctrl.branch   = 1'b1;
        ctrl.next_pc  = PC_BRANCH;
        ctrl.illegal  = 1'b0;
        unique case (funct3)
          3'b000:  ctrl.alu_op = ALU_EQ;   // beq
          3'b001:  ctrl.alu_op = ALU_NE;   // bne
          3'b100:  ctrl.alu_op = ALU_LT;   // blt
          3'b101:  ctrl.alu_op = ALU_GE;   // bge
          3'b110:  ctrl.alu_op = ALU_LTU;  // bltu
          3'b111:  ctrl.alu_op = ALU_GEU;  // bgeu
          default: ctrl.illegal = 1'b1;     // 010/011 非法
        endcase
      end

      // =====================================================================
      // LOAD: I 型，rd = MEM[rs1 + I-imm]，funct3 决定大小/符号
      // =====================================================================
      7'b0000011: begin
        ctrl.imm_type     = IMM_I;
        ctrl.alu_op       = ALU_ADD;       // 地址 = rs1 + imm
        ctrl.alu_op_b_sel = 1'b1;
        ctrl.reg_write    = 1'b1;
        ctrl.wb_sel       = WB_MEM;
        ctrl.mem_read     = 1'b1;
        ctrl.illegal      = 1'b0;
        unique case (funct3)
          3'b000:  begin ctrl.mem_size = SIZE_B; ctrl.mem_unsigned = 1'b0; end // lb
          3'b001:  begin ctrl.mem_size = SIZE_H; ctrl.mem_unsigned = 1'b0; end // lh
          3'b010:  begin ctrl.mem_size = SIZE_W; ctrl.mem_unsigned = 1'b0; end // lw
          3'b100:  begin ctrl.mem_size = SIZE_B; ctrl.mem_unsigned = 1'b1; end // lbu
          3'b101:  begin ctrl.mem_size = SIZE_H; ctrl.mem_unsigned = 1'b1; end // lhu
          default: ctrl.illegal = 1'b1;     // 011/110/111 非法
        endcase
      end

      // =====================================================================
      // STORE: S 型，MEM[rs1 + S-imm] = rs2，funct3 决定大小
      // =====================================================================
      7'b0100011: begin
        ctrl.imm_type     = IMM_S;
        ctrl.alu_op       = ALU_ADD;       // 地址 = rs1 + imm
        ctrl.alu_op_b_sel = 1'b1;
        ctrl.mem_write    = 1'b1;
        ctrl.illegal      = 1'b0;
        unique case (funct3)
          3'b000:  ctrl.mem_size = SIZE_B;  // sb
          3'b001:  ctrl.mem_size = SIZE_H;  // sh
          3'b010:  ctrl.mem_size = SIZE_W;  // sw
          default: ctrl.illegal = 1'b1;
        endcase
      end

      // =====================================================================
      // OP-IMM: I 型，rd = rs1 OP imm，funct3 决定运算
      // 注意 slli/srli/srai 的 imm 只有低 5 位有效，funct7[30] 区分 srl/sra
      // =====================================================================
      7'b0010011: begin
        ctrl.imm_type     = IMM_I;
        ctrl.alu_op_b_sel = 1'b1;          // operand B = imm
        ctrl.reg_write    = 1'b1;
        ctrl.wb_sel       = WB_ALU;
        ctrl.illegal      = 1'b0;
        unique case (funct3)
          3'b000:  ctrl.alu_op = ALU_ADD;   // addi
          3'b010:  ctrl.alu_op = ALU_SLT;   // slti
          3'b011:  ctrl.alu_op = ALU_SLTU;  // sltiu
          3'b100:  ctrl.alu_op = ALU_XOR;   // xori
          3'b110:  ctrl.alu_op = ALU_OR;    // ori
          3'b111:  ctrl.alu_op = ALU_AND;   // andi
          3'b001:  begin                    // slli
            if (funct7[6:0] == 7'b0000000) ctrl.alu_op = ALU_SLL;
            else                            ctrl.illegal = 1'b1;
          end
          3'b101:  begin                    // srli / srai
            if      (funct7[6:0] == 7'b0000000) ctrl.alu_op = ALU_SRL;
            else if (funct7[6:0] == 7'b0100000) ctrl.alu_op = ALU_SRA;
            else                                 ctrl.illegal = 1'b1;
          end
          default: ctrl.illegal = 1'b1;
        endcase
      end

      // =====================================================================
      // OP: R 型，rd = rs1 OP rs2
      //   funct7=0000000/0100000 → 基础 RV32I（add/sub/sll/...）
      //   funct7=0000001         → M 扩展（mul/mulh/.../div/rem）
      // =====================================================================
      7'b0110011: begin
        ctrl.alu_op_b_sel = 1'b0;          // operand B = rs2
        ctrl.reg_write    = 1'b1;
        ctrl.wb_sel       = WB_ALU;
        ctrl.illegal      = 1'b0;

        if (funct7 == 7'b0000001) begin
          // --- M 扩展：走乘除法单元 ---
          ctrl.use_multdiv = 1'b1;
          unique case (funct3)
            3'b000:  ctrl.multdiv_op = MD_MUL;     // mul
            3'b001:  ctrl.multdiv_op = MD_MULH;    // mulh
            3'b010:  ctrl.multdiv_op = MD_MULHSU;  // mulhsu
            3'b011:  ctrl.multdiv_op = MD_MULHU;   // mulhu
            3'b100:  ctrl.multdiv_op = MD_DIV;     // div
            3'b101:  ctrl.multdiv_op = MD_DIVU;    // divu
            3'b110:  ctrl.multdiv_op = MD_REM;     // rem
            3'b111:  ctrl.multdiv_op = MD_REMU;    // remu
            default: ctrl.illegal = 1'b1;
          endcase
        end else begin
          // --- 基础 RV32I：走 ALU ---
          unique case (funct3)
            3'b000:  begin
              if      (funct7[5] == 1'b0) ctrl.alu_op = ALU_ADD;  // add
              else if (funct7[5] == 1'b1) ctrl.alu_op = ALU_SUB;  // sub
              else                         ctrl.illegal = 1'b1;
            end
            3'b001:  begin
              if (funct7[5] == 1'b0) ctrl.alu_op = ALU_SLL;       // sll
              else                    ctrl.illegal = 1'b1;
            end
            3'b010:  begin
              if (funct7[5] == 1'b0) ctrl.alu_op = ALU_SLT;       // slt
              else                    ctrl.illegal = 1'b1;
            end
            3'b011:  begin
              if (funct7[5] == 1'b0) ctrl.alu_op = ALU_SLTU;      // sltu
              else                    ctrl.illegal = 1'b1;
            end
            3'b100:  begin
              if (funct7[5] == 1'b0) ctrl.alu_op = ALU_XOR;       // xor
              else                    ctrl.illegal = 1'b1;
            end
            3'b101:  begin
              if      (funct7[5] == 1'b0) ctrl.alu_op = ALU_SRL;  // srl
              else if (funct7[5] == 1'b1) ctrl.alu_op = ALU_SRA;  // sra
              else                         ctrl.illegal = 1'b1;
            end
            3'b110:  begin
              if (funct7[5] == 1'b0) ctrl.alu_op = ALU_OR;        // or
              else                    ctrl.illegal = 1'b1;
            end
            3'b111:  begin
              if (funct7[5] == 1'b0) ctrl.alu_op = ALU_AND;       // and
              else                    ctrl.illegal = 1'b1;
            end
            default: ctrl.illegal = 1'b1;
          endcase
        end
      end

      // =====================================================================
      // SYSTEM: I 型，ecall/ebreak/csr*（当前阶段标记为非法，后续扩展）
      // =====================================================================
      7'b1110011: begin
        ctrl.illegal = 1'b1;   // 暂不处理，标记非法
      end

      // =====================================================================
      // 未识别的 opcode
      // =====================================================================
      default: begin
        ctrl.illegal = 1'b1;
      end

    endcase

    ctrl_o = ctrl;
  end

endmodule : rvp_decoder
