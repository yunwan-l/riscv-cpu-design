// =============================================================================
// tb_decoder.sv — 译码器单元测试
// =============================================================================
// 用法（ModelSim，在 tb/ 目录下）：
//   vlib work
//   vlog -sv ../rtl/rvp_pkg.sv ../rtl/core/rvp_decoder.sv tb_decoder.sv
//   vsim -c -do "run -all; quit" tb_decoder
//
// 测试策略：用 RISC-V 工具链生成的真实机器码，检查关键控制信号。
// 机器码来源：riscv-none-elf-gcc -march=rv32i 汇编 decoder_test.S
// =============================================================================

`timescale 1ns/1ps

module tb_decoder;

  import rvp_pkg::*;

  logic [31:0] instr;
  ctrl_t       ctrl;

  int errors = 0;
  int tests  = 0;

  rvp_decoder dut (
    .instr_i (instr),
    .ctrl_o  (ctrl)
  );

  // 检查单个信号
  task automatic chk_s(input [255:0] name, input got, input exp);
    tests++;
    if (got !== exp) begin
      $display("  [FAIL] %-20s instr=%h : %0s got=%0d exp=%0d", name, instr, name, got, exp);
      errors++;
    end
  endtask

  // 检查一条指令的所有关键信号
  task automatic chk_instr(
    input [255:0]  name,
    input [31:0]   i_instr,
    input alu_op_e exp_alu_op,
    input logic    exp_reg_write,
    input logic    exp_mem_read,
    input logic    exp_mem_write,
    input wb_sel_e exp_wb_sel,
    input next_pc_e exp_next_pc,
    input logic    exp_branch,
    input logic    exp_illegal,
    input logic    exp_op_b_imm,
    input imm_type_e exp_imm_type
  );
    tests++;
    instr = i_instr; #10;
    if (ctrl.alu_op !== exp_alu_op || ctrl.reg_write !== exp_reg_write ||
        ctrl.mem_read !== exp_mem_read || ctrl.mem_write !== exp_mem_write ||
        ctrl.wb_sel !== exp_wb_sel || ctrl.next_pc !== exp_next_pc ||
        ctrl.branch !== exp_branch || ctrl.illegal !== exp_illegal ||
        ctrl.alu_op_b_sel !== exp_op_b_imm || ctrl.imm_type !== exp_imm_type) begin
      $display("  [FAIL] %0s instr=%h", name, i_instr);
      $display("         alu_op:   got=%0d exp=%0d", ctrl.alu_op, exp_alu_op);
      $display("         reg_write:got=%0d exp=%0d", ctrl.reg_write, exp_reg_write);
      $display("         mem_read: got=%0d exp=%0d", ctrl.mem_read, exp_mem_read);
      $display("         mem_write:got=%0d exp=%0d", ctrl.mem_write, exp_mem_write);
      $display("         wb_sel:   got=%0d exp=%0d", ctrl.wb_sel, exp_wb_sel);
      $display("         next_pc:  got=%0d exp=%0d", ctrl.next_pc, exp_next_pc);
      $display("         branch:   got=%0d exp=%0d", ctrl.branch, exp_branch);
      $display("         illegal:  got=%0d exp=%0d", ctrl.illegal, exp_illegal);
      $display("         op_b_imm: got=%0d exp=%0d", ctrl.alu_op_b_sel, exp_op_b_imm);
      $display("         imm_type: got=%0d exp=%0d", ctrl.imm_type, exp_imm_type);
      errors++;
    end else begin
      $display("  [ OK ] %0s", name);
    end
  endtask

  initial begin
    $display("==========================================================");
    $display(" Decoder Testbench Start");
    $display("==========================================================");

    // ===== OP-IMM (I型, rd=rs1 OP imm, reg_write=1, wb=ALU, op_b=imm) =====
    $display("--- OP-IMM ---");
    chk_instr("addi",  32'h00500093, ALU_ADD,  1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("slti",  32'h00a0a113, ALU_SLT,  1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("sltiu", 32'h00a0b193, ALU_SLTU, 1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("xori",  32'h0ff0c213, ALU_XOR,  1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("ori",   32'h0ff0e293, ALU_OR,   1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("andi",  32'h00f0f313, ALU_AND,  1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("slli",  32'h00309393, ALU_SLL,  1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("srli",  32'h0020d413, ALU_SRL,  1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("srai",  32'h4020d493, ALU_SRA,  1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_I);

    // ===== OP (R型, rd=rs1 OP rs2, reg_write=1, wb=ALU, op_b=rs2) =====
    $display("--- OP ---");
    chk_instr("add",   32'h00208533, ALU_ADD,  1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("sub",   32'h402085b3, ALU_SUB,  1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("sll",   32'h00209633, ALU_SLL,  1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("slt",   32'h0020a6b3, ALU_SLT,  1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("sltu",  32'h0020b733, ALU_SLTU, 1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("xor",   32'h0020c7b3, ALU_XOR,  1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("srl",   32'h0020d833, ALU_SRL,  1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("sra",   32'h4020d8b3, ALU_SRA,  1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("or",    32'h0020e933, ALU_OR,   1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);
    chk_instr("and",   32'h0020f9b3, ALU_AND,  1,0,0, WB_ALU, PC_SEQ,   0,0,0, IMM_I);

    // ===== LUI / AUIPC =====
    $display("--- LUI / AUIPC ---");
    chk_instr("lui",   32'h12345a37, ALU_ADD,  1,0,0, WB_IMM, PC_SEQ,   0,0,0, IMM_U);
    chk_instr("auipc", 32'h54321a97, ALU_ADD,  1,0,0, WB_ALU, PC_SEQ,   0,0,1, IMM_U);
    // auipc 特殊：op_a=PC(1)，检查一下
    tests++; instr = 32'h54321a97; #10;
    if (ctrl.alu_op_a_sel !== 1'b1) begin
      $display("  [FAIL] auipc alu_op_a_sel: got=%0d exp=1", ctrl.alu_op_a_sel);
      errors++;
    end else $display("  [ OK ] auipc op_a=PC");

    // ===== JAL / JALR =====
    $display("--- JAL / JALR ---");
    chk_instr("jal",   32'h0000006f, ALU_ADD,  1,0,0, WB_PC4, PC_JUMP,  0,0,0, IMM_J);
    chk_instr("jalr",  32'h00008067, ALU_ADD,  1,0,0, WB_PC4, PC_JALR,  0,0,1, IMM_I);

    // ===== BRANCH (no reg_write, branch=1, next_pc=BRANCH) =====
    $display("--- BRANCH ---");
    chk_instr("beq",   32'h00208463, ALU_EQ,   0,0,0, WB_ALU, PC_BRANCH,1,0,0, IMM_B);
    chk_instr("bne",   32'h00209463, ALU_NE,   0,0,0, WB_ALU, PC_BRANCH,1,0,0, IMM_B);
    chk_instr("blt",   32'h0020c463, ALU_LT,   0,0,0, WB_ALU, PC_BRANCH,1,0,0, IMM_B);
    chk_instr("bge",   32'h0020d463, ALU_GE,   0,0,0, WB_ALU, PC_BRANCH,1,0,0, IMM_B);
    chk_instr("bltu",  32'h0020e463, ALU_LTU,  0,0,0, WB_ALU, PC_BRANCH,1,0,0, IMM_B);
    chk_instr("bgeu",  32'h0020f463, ALU_GEU,  0,0,0, WB_ALU, PC_BRANCH,1,0,0, IMM_B);

    // ===== LOAD (mem_read=1, wb=MEM, op_b=imm) =====
    $display("--- LOAD ---");
    chk_instr("lb",    32'h00010083, ALU_ADD,  1,1,0, WB_MEM, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("lh",    32'h00011083, ALU_ADD,  1,1,0, WB_MEM, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("lw",    32'h00012083, ALU_ADD,  1,1,0, WB_MEM, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("lbu",   32'h00014083, ALU_ADD,  1,1,0, WB_MEM, PC_SEQ,   0,0,1, IMM_I);
    chk_instr("lhu",   32'h00015083, ALU_ADD,  1,1,0, WB_MEM, PC_SEQ,   0,0,1, IMM_I);

    // ===== STORE (mem_write=1, no reg_write, op_b=imm) =====
    $display("--- STORE ---");
    chk_instr("sb",    32'h00110023, ALU_ADD,  0,0,1, WB_ALU, PC_SEQ,   0,0,1, IMM_S);
    chk_instr("sh",    32'h00111023, ALU_ADD,  0,0,1, WB_ALU, PC_SEQ,   0,0,1, IMM_S);
    chk_instr("sw",    32'h00112023, ALU_ADD,  0,0,1, WB_ALU, PC_SEQ,   0,0,1, IMM_S);

    // ===== 非法指令 =====
    $display("--- Illegal ---");
    tests++; instr = 32'h00000000; #10;  // 全0，opcode=0000000 非法
    if (ctrl.illegal !== 1'b1) begin
      $display("  [FAIL] all-zeros should be illegal");
      errors++;
    end else $display("  [ OK ] all-zeros illegal");

    // ===== 汇总 =====
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_decoder
