/**
 * rvp_pkg.sv - RVP Global Package
 *
 * Central definitions for all constants, types, and enums used across
 * the RVP processor. Modeled after ibex_pkg.sv.
 *
 * All modules import this package:  import rvp_pkg::*;
 */

package rvp_pkg;

  // ==========================================================================
  // Global Width Constants
  // ==========================================================================

  parameter int unsigned DATA_W       = 32;    // Data bus width
  parameter int unsigned ADDR_W       = 32;    // Address bus width
  parameter int unsigned INSTR_W      = 32;    // Instruction width
  parameter int unsigned REG_ADDR_W   = 5;     // Register address width (x0-x31)
  parameter int unsigned REG_DATA_W   = 32;    // Register data width

  // ==========================================================================
  // RV32I Opcode Definitions
  // ==========================================================================

  typedef enum logic [6:0] {
    OPCODE_LUI     = 7'b0110111,   // Load Upper Immediate
    OPCODE_AUIPC   = 7'b0010111,   // Add Upper Immediate to PC
    OPCODE_JAL     = 7'b1101111,   // Jump and Link
    OPCODE_JALR    = 7'b1100111,   // Jump and Link Register
    OPCODE_BRANCH  = 7'b1100011,   // Conditional Branch (BEQ, BNE, etc.)
    OPCODE_LOAD    = 7'b0000011,   // Load (LB, LH, LW, LBU, LHU)
    OPCODE_STORE   = 7'b0100011,   // Store (SB, SH, SW)
    OPCODE_OP_IMM  = 7'b0010011,   // ALU Immediate (ADDI, SLTI, etc.)
    OPCODE_OP      = 7'b0110011,   // ALU Register (ADD, SUB, etc.)
    OPCODE_MISC    = 7'b0001111,   // FENCE (treated as NOP for now)
    OPCODE_SYSTEM  = 7'b1110011,    // ECALL, EBREAK, CSR
    OPCODE_MADD    = 7'b1000011,   // M-extension: MUL (R-type OP variant)
    OPCODE_CUSTOM0 = 7'b0001011    // Custom instruction space (PCPI)
  } opcode_e;

  // ==========================================================================
  // ALU Operations
  // ==========================================================================

  typedef enum logic [3:0] {
    ALU_ADD   = 4'd0,   // Addition
    ALU_SUB   = 4'd1,   // Subtraction
    ALU_SLL   = 4'd2,   // Shift Left Logical
    ALU_SLT   = 4'd3,   // Set Less Than (signed)
    ALU_SLTU  = 4'd4,   // Set Less Than Unsigned
    ALU_XOR   = 4'd5,   // XOR
    ALU_SRL   = 4'd6,   // Shift Right Logical
    ALU_SRA   = 4'd7,   // Shift Right Arithmetic
    ALU_OR    = 4'd8,   // OR
    ALU_AND   = 4'd9,   // AND
    ALU_LUI   = 4'd10,  // Pass-through immediate (LUI)
    ALU_MUL   = 4'd11,  // MUL (M-extension)
    ALU_MULH  = 4'd12,  // MULH (M-extension)
    ALU_DIV   = 4'd13,  // DIV (M-extension)
    ALU_REM   = 4'd14,  // REM (M-extension)
    ALU_NOP   = 4'd15   // No operation
  } alu_op_e;

  // ==========================================================================
  // Branch Types
  // ==========================================================================

  typedef enum logic [2:0] {
    BRANCH_NONE = 3'd0,  // Not a branch
    BRANCH_BEQ  = 3'd1,  // Branch if Equal
    BRANCH_BNE  = 3'd2,  // Branch if Not Equal
    BRANCH_BLT  = 3'd3,  // Branch if Less Than (signed)
    BRANCH_BGE  = 3'd4,  // Branch if Greater or Equal (signed)
    BRANCH_BLTU = 3'd5,  // Branch if Less Than (unsigned)
    BRANCH_BGEU = 3'd6   // Branch if Greater or Equal (unsigned)
  } branch_type_e;

  // ==========================================================================
  // Immediate Types
  // ==========================================================================

  typedef enum logic [2:0] {
    IMM_NONE = 3'd0,  // No immediate
    IMM_I    = 3'd1,  // I-type:  [31:20] sign-extended
    IMM_S    = 3'd2,  // S-type:  [31:25],[11:7] sign-extended
    IMM_B    = 3'd3,  // B-type:  [31],[7],[30:25],[11:8],0 sign-extended
    IMM_U    = 3'd4,  // U-type:  [31:12],0
    IMM_J    = 3'd5,  // J-type:  [31],[19:12],[20],[30:21],0 sign-extended
    IMM_Z    = 3'd6   // Z-type:  [19:15] zero-extended (CSR)
  } imm_type_e;

  // ==========================================================================
  // Writeback Source Selection
  // ==========================================================================

  typedef enum logic [1:0] {
    WB_ALU   = 2'd0,  // Write ALU result
    WB_MEM   = 2'd1,  // Write memory load data
    WB_PC4   = 2'd2,  // Write PC+4 (JAL/JALR)
    WB_CSR   = 2'd3   // Write CSR read data
  } wb_src_e;

  // ==========================================================================
  // Hazard / Forwarding Types
  // ==========================================================================

  typedef enum logic [1:0] {
    FWD_NONE    = 2'd0,  // No forward, use register file value
    FWD_EX_MEM  = 2'd1,  // Forward from EX/MEM register
    FWD_MEM_WB  = 2'd2,  // Forward from MEM/WB register
    FWD_WB      = 2'd3   // Forward from WB stage (if 5-stage)
  } forward_sel_e;

  // ==========================================================================
  // Memory Access Types
  // ==========================================================================

  typedef enum logic [2:0] {
    MEM_NONE = 3'd0,  // No memory access
    MEM_B    = 3'd1,  // Byte (8-bit)
    MEM_H    = 3'd2,  // Halfword (16-bit)
    MEM_W    = 3'd3,  // Word (32-bit)
    MEM_BU   = 3'd4,  // Byte unsigned
    MEM_HU   = 3'd5   // Halfword unsigned
  } mem_size_e;

  // ==========================================================================
  // Pipeline Control Signals Structure
  // ==========================================================================

  typedef struct packed {
    logic        alu_src_a;       // 0 = reg1, 1 = PC
    logic        alu_src_b;      // 0 = reg2, 1 = immediate
    logic        mem_read;        // Load enable
    logic        mem_write;       // Store enable
    logic        reg_write;       // Register file write enable
    logic        branch;          // Conditional branch
    logic        jump;           // Unconditional jump (JAL/JALR)
    logic        jalr;           // JALR (indirect jump)
    wb_src_e     wb_src;          // Writeback data source
    alu_op_e     alu_op;          // ALU operation
    branch_type_e branch_type;    // Branch condition type
    mem_size_e   mem_size;        // Memory access size
    imm_type_e   imm_type;        // Immediate format type
    logic        m_extension;     // M-extension instruction flag
  } ctrl_signals_t;

  // ==========================================================================
  // Controller FSM States
  // ==========================================================================

  typedef enum logic [2:0] {
    CTRL_RESET    = 3'd0,  // Reset state
    CTRL_FETCH    = 3'd1,  // Fetch instruction
    CTRL_DECODE   = 3'd2,  // Decode
    CTRL_EXECUTE  = 3'd3,  // Execute
    CTRL_MEM      = 3'd4,  // Memory access
    CTRL_WB       = 3'd5,  // Writeback
    CTRL_STALL    = 3'd6,  // Pipeline stall
    CTRL_FLUSH    = 3'd7   // Pipeline flush (branch taken)
  } ctrl_state_e;

  // ==========================================================================
  // Utility Functions
  // ==========================================================================

  // Sign-extend a value from a given width
  function automatic logic [31:0] sign_extend(input logic [31:0] value, input int unsigned from_width);
    return {{(32 - from_width){value[from_width - 1]}}, value[from_width - 1:0]};
  endfunction

  // Count leading zeros
  function automatic logic [4:0] clz32(input logic [31:0] val);
    logic [4:0] result;
    result = 0;
    for (int i = 31; i >= 0; i--) begin
      if (val[i] == 1'b1) begin
        result = 5'd31 - 5'(i);
        break;
      end
    end
    return result;
  endfunction

endpackage
