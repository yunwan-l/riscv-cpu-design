// =============================================================================
// tb_imm_generator.sv — 立即数生成器单元测试
// =============================================================================
// 用法（ModelSim，在 tb/ 目录下）：
//   vlib work
//   vlog -sv ../rtl/rvp_pkg.sv ../rtl/core/rvp_imm_generator.sv tb_imm_generator.sv
//   vsim -c -do "run -all; quit" tb_imm_generator
//
// 测试策略：用真实的 RISC-V 指令机器码，手工计算期望立即数来验证。
// 机器码用 RISC-V 编码规则手工推导，确保位拼接正确。
// =============================================================================

`timescale 1ns/1ps

module tb_imm_generator;

  import rvp_pkg::*;

  logic [31:0]    instr;
  imm_type_e      imm_type;
  logic [31:0]    imm;

  int errors = 0;
  int tests  = 0;

  rvp_imm_generator dut (
    .instr_i    (instr),
    .imm_type_i (imm_type),
    .imm_o      (imm)
  );

  task automatic chk(input [31:0] exp, input [255:0] name);
    tests++;
    if (imm !== exp) begin
      $display("  [FAIL] %0s : instr=%h => got %h, exp %h", name, instr, imm, exp);
      errors++;
    end else begin
      $display("  [ OK ] %0s : %h", name, imm);
    end
  endtask

  initial begin
    $display("==========================================================");
    $display(" Immediate Generator Testbench Start");
    $display("==========================================================");

    // ===== I 型 =====
    // addi x1, x0, 5  → 00000000010100000000000010010011 = 0x00500093
    // imm[11:0]=inst[31:20]=0x005 → 正数 5
    $display("--- I-type ---");
    instr = 32'h00500093; imm_type = IMM_I; #10; chk(32'd5, "addi x1,x0,5");

    // addi x2, x0, -1 → 11111111111100000000000100010011 = 0xFFF10213
    // imm[11:0]=0xFFF → 符号扩展为 0xFFFFFFFF = -1
    instr = 32'hFFF10113; imm_type = IMM_I; #10; chk(32'hFFFFFFFF, "addi x2,x0,-1");

    // lw x3, 8(x1) → imm=8, rs1=x1, rd=x3, opcode=0000011
    // 000000001000000010000001100000011 = 0x0080A303
    instr = 32'h0080A303; imm_type = IMM_I; #10; chk(32'd8, "lw x3,8(x1)");

    // ===== S 型 =====
    // sw x2, 12(x1) → imm[11:5]=0, imm[4:0]=01100=12
    // rs2=x2(00010), rs1=x1(00001), funct3=010, imm[4:0]=01100, opcode=0100011
    // 0000000 00010 00001 010 01100 0100011 = 0x0020A223
    $display("--- S-type ---");
    instr = 32'h0020A623; imm_type = IMM_S; #10; chk(32'd12, "sw x2,12(x1)");

    // sw x2, -4(x1) → imm=-4=0xFFFFFFFC, imm[11:5]=1111111, imm[4:0]=11100
    // 1111111 00010 00001 010 11100 0100011 = 0xFE20A2A3
    instr = 32'hFE20AE23; imm_type = IMM_S; #10; chk(32'hFFFFFFFC, "sw x2,-4(x1)");

    // ===== B 型 =====
    // beq x1, x2, 8 → imm=8, bit0=0, imm[4:1]=0100, imm[10:5]=0, imm[11]=0, imm[12]=0
    // imm[12]=0, imm[10:5]=000000, rs2=x2, rs1=x1, funct3=000,
    // imm[4:1]=0100, imm[11]=0, opcode=1100011
    // 0 000000 00010 00001 000 0100 0 1100011 = 0x00208463
    $display("--- B-type ---");
    instr = 32'h00208463; imm_type = IMM_B; #10; chk(32'd8, "beq x1,x2,8");

    // beq x1, x2, -8 → imm=-8=0xFFFFFFF8
    // imm[12]=1, imm[11]=1, imm[10:5]=111111, imm[4:1]=1100, imm[0]=0
    // 1 111111 00010 00001 000 1100 1 1100011 = 0xFE208E63
    instr = 32'hFE208CE3; imm_type = IMM_B; #10; chk(32'hFFFFFFF8, "beq x1,x2,-8");

    // ===== U 型 =====
    // lui x1, 0x12345 → imm[31:12]=0x12345, 低12位=0
    // 00010010001101000101 00001 0110111 = 0x123450B7
    $display("--- U-type ---");
    instr = 32'h123450B7; imm_type = IMM_U; #10; chk(32'h12345000, "lui x1,0x12345");

    // lui x2, 0xFFFFF → 最高位是1，但U型不符号扩展，就是 0xFFFFF000
    instr = 32'hFFFFF137; imm_type = IMM_U; #10; chk(32'hFFFFF000, "lui x2,0xFFFFF");

    // ===== J 型 =====
    // jal x1, 8 → imm=8, bit0=0, imm[10:1]=0000000100, imm[11]=0, imm[19:12]=0, imm[20]=0
    // imm[20]=0, imm[10:1]=0000000100, imm[11]=0, imm[19:12]=00000000, rd=x1, opcode=1101111
    // 0 0000000100 0 00000000 00001 1101111 = 0x008000EF
    $display("--- J-type ---");
    instr = 32'h008000EF; imm_type = IMM_J; #10; chk(32'd8, "jal x1,8");

    // jal x0, -4 → imm=-4=0xFFFFFFFC
    // imm[20]=1, imm[19:12]=11111111, imm[11]=1, imm[10:1]=1111111110, imm[0]=0
    // 1 11111111 1 1111111110 00000 1101111
    // 拼接：0xFFFFFFFE？让我重算
    // imm[20]=1, imm[19:12]=11111111, imm[11]=1, imm[10:1]=1111111110, imm[0]=0
    // = 1 11111111 1 1111111110 0 = 20位
    // 符号扩展(11个1) + 上述 = 0xFFFFFFFE
    // 编码到指令：inst[31]=imm[20]=1
    //   inst[30:21]=imm[10:1]=1111111110
    //   inst[20]=imm[11]=1
    //   inst[19:12]=imm[19:12]=11111111
    //   inst[11:7]=rd=00000
    //   inst[6:0]=1101111
    // = 1_1111111110_1_11111111_00000_1101111
    // = 0xFFFFFFE7... 让我精确算
    // 1 1111111110 1 11111111 00000 1101111
    // 位 [31]=1, [30:21]=1111111110, [20]=1, [19:12]=11111111, [11:7]=00000, [6:0]=1101111
    // = 1111 1111 1110 1111 1111 0000 0110 1111
    // = 0xFFFEF06F
    instr = 32'hFFDFF06F; imm_type = IMM_J; #10; chk(32'hFFFFFFFC, "jal x0,-4");

    // ===== 汇总 =====
    $display("==========================================================");
    if (errors == 0)
      $display(" ALL PASSED  (%0d tests)", tests);
    else
      $display(" FAILED: %0d / %0d tests", errors, tests);
    $display("==========================================================");
    $finish;
  end

endmodule : tb_imm_generator
