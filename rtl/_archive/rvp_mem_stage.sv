/**
 * rvp_mem_stage.sv - RVP Memory Access Stage
 *
 * 访存阶段，负责与数据存储器的交互。
 *
 * 主要功能:
 *   1. 内存访问控制 - 生成内存请求、地址、写数据和字节使能
 *   2. 字节使能生成 - 根据访问大小和地址低位生成字节使能
 *   3. 数据对齐 - Load数据符号扩展和字节对齐
 *
 * 支持的内存访问指令:
 *   LB, LH, LW, LBU, LHU, SB, SH, SW
 */

`include "rvp_config.svh"

module rvp_mem_stage import rvp_pkg::*; (
    input  logic              clk_i,
    input  logic              rst_ni,

    // 来自EX阶段的输入
    input  logic [31:0]       alu_result_i,
    input  logic [31:0]       mem_wdata_i,
    input  logic              mem_req_i,
    input  logic              mem_we_i,
    input  mem_size_e         mem_size_i,
    input  logic [31:0]       pc4_i,
    input  logic [REG_ADDR_W-1:0] rd_addr_i,
    input  logic              rf_we_i,
    input  wb_src_e           wb_src_i,
    input  logic              instr_valid_i,

    // 数据总线接口
    output logic              mem_req_o,
    input  logic              mem_gnt_i,
    input  logic              mem_rvalid_i,
    output logic [31:0]       mem_addr_o,
    output logic [31:0]       mem_wdata_o,
    input  logic [31:0]       mem_rdata_i,
    output logic              mem_we_o,
    output logic [3:0]        mem_be_o,

    // 输出到WB阶段
    output logic [31:0]       alu_result_o,
    output logic [31:0]       mem_rdata_o,
    output logic [31:0]       pc4_o,
    output logic [REG_ADDR_W-1:0] rd_addr_o,
    output logic              rf_we_o,
    output wb_src_e           wb_src_o,
    output logic              instr_valid_o,

    // 错误输出
    output logic              load_err_o,
    output logic              store_err_o,

    // 流水线控制
    input  logic              stall_i,
    input  logic              flush_i
);

  import rvp_pkg::*;

  // ==========================================================================
  // EX/MEM流水线寄存器
  // ==========================================================================
  logic [31:0]        alu_result_q;
  logic [31:0]        mem_wdata_q;
  logic               mem_req_q;
  logic               mem_we_q;
  mem_size_e          mem_size_q;
  logic [31:0]        pc4_q;
  logic [REG_ADDR_W-1:0] rd_addr_q;
  logic               rf_we_q;
  wb_src_e            wb_src_q;
  logic               instr_valid_q;

  // 字节使能
  logic [3:0]         byte_enable;
  logic [1:0]         addr_offset;

  // 对齐后的数据
  logic [31:0]        rdata_aligned;
  logic [31:0]        wdata_aligned;

  // ==========================================================================
  // EX/MEM 流水线寄存器
  // ==========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      alu_result_q  <= 32'b0;
      mem_wdata_q   <= 32'b0;
      mem_req_q     <= 1'b0;
      mem_we_q      <= 1'b0;
      mem_size_q    <= MEM_NONE;
      pc4_q         <= 32'b0;
      rd_addr_q     <= 5'b0;
      rf_we_q       <= 1'b0;
      wb_src_q      <= WB_ALU;
      instr_valid_q <= 1'b0;
    end else if (flush_i) begin
      mem_req_q     <= 1'b0;
      rf_we_q       <= 1'b0;
      instr_valid_q <= 1'b0;
    end else if (!stall_i) begin
      alu_result_q  <= alu_result_i;
      mem_wdata_q   <= mem_wdata_i;
      mem_req_q     <= mem_req_i;
      mem_we_q      <= mem_we_i;
      mem_size_q    <= mem_size_i;
      pc4_q         <= pc4_i;
      rd_addr_q     <= rd_addr_i;
      rf_we_q       <= rf_we_i;
      wb_src_q      <= wb_src_i;
      instr_valid_q <= instr_valid_i;
    end
  end

  // ==========================================================================
  // 字节使能生成器
  // ==========================================================================
  always_comb begin
    byte_enable = 4'b0000;
    addr_offset = alu_result_q[1:0];

    unique case (mem_size_q)
      MEM_B, MEM_BU: begin
        unique case (addr_offset)
          2'b00: byte_enable = 4'b0001;
          2'b01: byte_enable = 4'b0010;
          2'b10: byte_enable = 4'b0100;
          2'b11: byte_enable = 4'b1000;
        endcase
      end
      MEM_H, MEM_HU: begin
        unique case (addr_offset)
          2'b00: byte_enable = 4'b0011;
          2'b10: byte_enable = 4'b1100;
          default: byte_enable = 4'b0000; // 未对齐错误
        endcase
      end
      MEM_W: begin
        byte_enable = 4'b1111;
      end
      default: byte_enable = 4'b0000;
    endcase
  end

  // ==========================================================================
  // Store数据对齐 (写方向)
  // ==========================================================================
  always_comb begin
    wdata_aligned = mem_wdata_q;

    unique case (mem_size_q)
      MEM_B, MEM_BU: begin
        unique case (addr_offset)
          2'b00: wdata_aligned = {24'b0, mem_wdata_q[7:0]};
          2'b01: wdata_aligned = {16'b0, mem_wdata_q[7:0], 8'b0};
          2'b10: wdata_aligned = {8'b0, mem_wdata_q[7:0], 16'b0};
          2'b11: wdata_aligned = {mem_wdata_q[7:0], 24'b0};
        endcase
      end
      MEM_H, MEM_HU: begin
        unique case (addr_offset)
          2'b00: wdata_aligned = {16'b0, mem_wdata_q[15:0]};
          2'b10: wdata_aligned = {mem_wdata_q[15:0], 16'b0};
          default: wdata_aligned = mem_wdata_q;
        endcase
      end
      MEM_W: wdata_aligned = mem_wdata_q;
      default: wdata_aligned = mem_wdata_q;
    endcase
  end

  // ==========================================================================
  // Load数据对齐与符号扩展 (读方向)
  // ==========================================================================
  always_comb begin
    rdata_aligned = mem_rdata_i;

    unique case (mem_size_q)
      MEM_B: begin
        unique case (addr_offset)
          2'b00: rdata_aligned = {{24{mem_rdata_i[7]}},  mem_rdata_i[7:0]};
          2'b01: rdata_aligned = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]};
          2'b10: rdata_aligned = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]};
          2'b11: rdata_aligned = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]};
        endcase
      end
      MEM_BU: begin
        unique case (addr_offset)
          2'b00: rdata_aligned = {24'b0, mem_rdata_i[7:0]};
          2'b01: rdata_aligned = {24'b0, mem_rdata_i[15:8]};
          2'b10: rdata_aligned = {24'b0, mem_rdata_i[23:16]};
          2'b11: rdata_aligned = {24'b0, mem_rdata_i[31:24]};
        endcase
      end
      MEM_H: begin
        unique case (addr_offset)
          2'b00: rdata_aligned = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
          2'b10: rdata_aligned = {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]};
          default: rdata_aligned = mem_rdata_i;
        endcase
      end
      MEM_HU: begin
        unique case (addr_offset)
          2'b00: rdata_aligned = {16'b0, mem_rdata_i[15:0]};
          2'b10: rdata_aligned = {16'b0, mem_rdata_i[31:16]};
          default: rdata_aligned = mem_rdata_i;
        endcase
      end
      MEM_W: rdata_aligned = mem_rdata_i;
      default: rdata_aligned = mem_rdata_i;
    endcase
  end

  // ==========================================================================
  // 内存请求控制
  // ==========================================================================
  assign mem_req_o   = mem_req_q & instr_valid_q;
  assign mem_addr_o  = alu_result_q;
  assign mem_wdata_o = wdata_aligned;
  assign mem_we_o    = mem_we_q;
  assign mem_be_o    = byte_enable;

  // ==========================================================================
  // 地址对齐检查 (字访问需4字节对齐)
  // ==========================================================================
  assign load_err_o  = mem_req_q & ~mem_we_q & (addr_offset != 2'b00) &
                       (mem_size_q == MEM_W);
  assign store_err_o = mem_req_q & mem_we_q & (addr_offset != 2'b00) &
                       (mem_size_q == MEM_W);

  // ==========================================================================
  // 输出到WB阶段
  // ==========================================================================
  assign alu_result_o  = alu_result_q;
  assign mem_rdata_o   = rdata_aligned;
  assign pc4_o         = pc4_q;
  assign rd_addr_o     = rd_addr_q;
  assign rf_we_o       = rf_we_q & instr_valid_q;  // flush already clears rf_we_q
  assign wb_src_o      = wb_src_q;
  assign instr_valid_o = instr_valid_q;

endmodule
