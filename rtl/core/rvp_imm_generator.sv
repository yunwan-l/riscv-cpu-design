// =============================================================================
// rvp_imm_generator.sv — RVP 立即数生成器
// =============================================================================
// 功能：根据 imm_type_i，从 32 位指令中提取并拼接立即数，做符号扩展。
//
// 接口：
//   instr_i     : 32 位原始指令
//   imm_type_i  : 立即数类型（IMM_I/S/B/U/J，见 rvp_pkg::imm_type_e）
//   imm_o       : 提取并符号扩展后的 32 位立即数
//
// 核心难点：RISC-V 把立即数"打散"放在指令的不同位置以节省编码空间，
// 尤其是 B 型（分支）和 J 型（jal），立即数位顺序很乱，必须仔细对照手册拼。
//
// 符号扩展：I/S/B/J 型的立即数是"有符号"的，最高位（符号位）是 inst[31]，
// 需要用 inst[31] 填充高位。U 型（lui/auipc）特殊：它直接是高 20 位，
// 低 12 位补 0，不符号扩展（因为已经是 32 位的"高半部分"）。
// =============================================================================

module rvp_imm_generator (
  input  logic [31:0]       instr_i,
  input  rvp_pkg::imm_type_e imm_type_i,
  output logic [31:0]       imm_o
);

  import rvp_pkg::*;

  // 消费未使用的指令位 [6:0]（opcode 字段，立即数生成器不需要）
  wire _unused_opcode = |instr_i[6:0];

  // -------------------------------------------------------------------------
  // 各类型立即数的原始位提取（组合逻辑）
  // -------------------------------------------------------------------------
  // 先把每种格式的立即数按手册位置拼好，再由 imm_type_i 选一个输出。
  // 拼接顺序 {高位...低位}，符号位在最左。

  // I 型：imm[11:0] = inst[31:20]，符号位 inst[31]
  logic [31:0] imm_i;
  assign imm_i = {{20{instr_i[31]}}, instr_i[31:20]};

  // S 型：imm[11:5]=inst[31:25], imm[4:0]=inst[11:7]，符号位 inst[31]
  logic [31:0] imm_s;
  assign imm_s = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};

  // B 型：imm[12]=inst[31], imm[11]=inst[7], imm[10:5]=inst[30:25],
  //       imm[4:1]=inst[11:8], imm[0]=0（2字节对齐，bit0 恒 0）
  logic [31:0] imm_b;
  assign imm_b = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                  instr_i[30:25], instr_i[11:8], 1'b0};

  // U 型：imm[31:12]=inst[31:12]，低 12 位补 0
  // 注意：U 型不符号扩展，直接就是 inst[31:12] 后接 12 个 0
  logic [31:0] imm_u;
  assign imm_u = {instr_i[31:12], 12'b0};

  // J 型：imm[20]=inst[31], imm[19:12]=inst[19:12], imm[11]=inst[20],
  //       imm[10:1]=inst[30:21], imm[0]=0
  logic [31:0] imm_j;
  assign imm_j = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                  instr_i[20], instr_i[30:21], 1'b0};

  // -------------------------------------------------------------------------
  // 多路选择
  // -------------------------------------------------------------------------
  always_comb begin
    unique case (imm_type_i)
      IMM_I:   imm_o = imm_i;
      IMM_S:   imm_o = imm_s;
      IMM_B:   imm_o = imm_b;
      IMM_U:   imm_o = imm_u;
      IMM_J:   imm_o = imm_j;
      default: imm_o = 32'b0;
    endcase
  end

endmodule : rvp_imm_generator
