/**
 * rvp_mem_stage.sv - RVP Memory Access Stage
 *
 * 访存阶段，负责与数据存储器的交互。
 * 参考ibex_load_store_unit.sv的设计。
 *
 * 主要功能:
 *   1. 内存访问控制 - 生成内存请求、地址、写数据和字节使能
 *   2. 字节使能生成 - 根据访问大小和地址低位生成字节使能
 *   3. 数据对齐 - Load数据符号扩展和字节对齐
 *   4. Store数据对齐 - 根据地址低位对齐Store数据
 *
 * 支持的内存访问指令:
 *   - LB  : 加载字节 (符号扩展)
 *   - LH  : 加载半字 (符号扩展)
 *   - LW  : 加载字
 *   - LBU : 加载字节 (零扩展)
 *   - LHU : 加载半字 (零扩展)
 *   - SB  : 存储字节
 *   - SH  : 存储半字
 *   - SW  : 存储字
 *
 * 数据流:
 *   EX → [EX/MEM reg] → MEM(访存) → [MEM/WB reg] → WB
 *
 * 内部子模块:
 *   - lsu_ctrl     : 访存控制
 *   - byte_en_gen  : 字节使能生成器
 *   - data_align   : 数据对齐与符号扩展
 */

`include "rvp_config.svh"

module rvp_mem_stage import rvp_pkg::*; (
    // ==========================================================================
    // 时钟与复位
    // ==========================================================================
    input  logic              clk_i,           // 时钟
    input  logic              rst_ni,          // 异步低复位

    // ==========================================================================
    // 来自EX阶段的输入
    // ==========================================================================
    input  logic [31:0]       alu_result_i,    // ALU结果 (作为内存地址)
    input  logic [31:0]       mem_wdata_i,     // 内存写数据 (rs2值)
    input  logic              mem_req_i,        // 内存请求
    input  logic              mem_we_i,         // 内存写使能
    input  mem_size_e         mem_size_i,       // 内存访问大小
    input  logic [31:0]       pc4_i,            // PC+4 (传递到WB)
    input  logic [REG_ADDR_W-1:0] rd_addr_i,   // rd地址 (传递到WB)
    input  logic              rf_we_i,          // 寄存器写使能
    input  wb_src_e           wb_src_i,         // 写回源选择
    input  logic              instr_valid_i,    // 指令有效

    // ==========================================================================
    // 数据总线接口 (连接到数据存储器/总线)
    // ==========================================================================
    output logic              mem_req_o,        // 内存请求
    input  logic              mem_gnt_i,        // 内存授权
    input  logic              mem_rvalid_i,     // 内存读有效
    output logic [31:0]       mem_addr_o,       // 内存地址
    output logic [31:0]       mem_wdata_o,      // 内存写数据
    input  logic [31:0]       mem_rdata_i,      // 内存读数据
    output logic              mem_we_o,         // 内存写使能
    output logic [3:0]        mem_be_o,         // 内存字节使能

    // ==========================================================================
    // 输出到WB阶段
    // ==========================================================================
    output logic [31:0]       alu_result_o,    // ALU结果 (传递到WB)
    output logic [31:0]       mem_rdata_o,      // 内存读数据 (对齐后)
    output logic [31:0]       pc4_o,           // PC+4 (传递到WB)
    output logic [REG_ADDR_W-1:0] rd_addr_o,   // rd地址 (传递到WB)
    output logic              rf_we_o,         // 寄存器写使能
    output wb_src_e           wb_src_o,         // 写回源选择
    output logic              instr_valid_o,    // 指令有效

    // ==========================================================================
    // 错误输出
    // ==========================================================================
    output logic              load_err_o,      // 加载错误
    output logic              store_err_o,     // 存储错误

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

  // EX/MEM流水线寄存器
  logic [31:0]        alu_result_q;       // ALU结果寄存器
  logic [31:0]        mem_wdata_q;        // 写数据寄存器
  logic               mem_req_q;          // 内存请求寄存器
  logic               mem_we_q;           // 写使能寄存器
  mem_size_e          mem_size_q;         // 访问大小寄存器
  logic [31:0]        pc4_q;              // PC+4寄存器
  logic [REG_ADDR_W-1:0] rd_addr_q;       // rd地址寄存器
  logic               rf_we_q;            // 写使能寄存器
  wb_src_e            wb_src_q;           // 写回源寄存器
  logic               instr_valid_q;     // 指令有效寄存器

  // 字节使能
  logic [3:0]         byte_enable;        // 字节使能信号

  // 对齐后的读数据
  logic [31:0]        rdata_aligned;      // 对齐后的读数据
  logic [31:0]        wdata_aligned;       // 对齐后的写数据

  // 地址低位 (用于字节对齐)
  logic [1:0]         addr_offset;        // 地址低2位

  // ==========================================================================
  // EX/MEM 流水线寄存器
  // ==========================================================================
  // TODO: 锁存EX阶段的数据
  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     alu_result_q  <= 32'b0;
  //     mem_wdata_q   <= 32'b0;
  //     mem_req_q     <= 1'b0;
  //     mem_we_q      <= 1'b0;
  //     mem_size_q     <= MEM_NONE;
  //     pc4_q          <= 32'b0;
  //     rd_addr_q      <= 5'b0;
  //     rf_we_q       <= 1'b0;
  //     wb_src_q      <= WB_ALU;
  //     instr_valid_q  <= 1'b0;
  //   end else if (flush_i) begin
  //     mem_req_q     <= 1'b0;
  //     rf_we_q       <= 1'b0;
  //     instr_valid_q  <= 1'b0;
  //   end else if (!stall_i) begin
  //     alu_result_q  <= alu_result_i;
  //     mem_wdata_q   <= mem_wdata_i;
  //     mem_req_q     <= mem_req_i;
  //     mem_we_q      <= mem_we_i;
  //     mem_size_q     <= mem_size_i;
  //     pc4_q          <= pc4_i;
  //     rd_addr_q      <= rd_addr_i;
  //     rf_we_q       <= rf_we_i;
  //     wb_src_q      <= wb_src_i;
  //     instr_valid_q  <= instr_valid_i;
  //   end
  // end

  // ==========================================================================
  // 字节使能生成器 (byte_en_gen)
  // ==========================================================================
  // 根据访问大小和地址低位生成字节使能
  // 地址对齐: 字地址(addr[1:0]=00)对应be=1111
  //           半字地址(addr[1:0]=01)对应be=0110或1100
  //           字节地址(addr[1:0]=10)对应be=0100或0010或0001
  always_comb begin
    byte_enable = 4'b0000;
    addr_offset = alu_result_q[1:0];

    // TODO: 根据mem_size_q和addr_offset生成字节使能
    // unique case (mem_size_q)
    //   MEM_B: begin
    //     // 字节访问: 只使能对应字节
    //     case (addr_offset)
    //       2'b00: byte_enable = 4'b0001;
    //       2'b01: byte_enable = 4'b0010;
    //       2'b10: byte_enable = 4'b0100;
    //       2'b11: byte_enable = 4'b1000;
    //     endcase
    //   end
    //   MEM_H: begin
    //     // 半字访问: 使能对应2字节
    //     case (addr_offset)
    //       2'b00: byte_enable = 4'b0011;
    //       2'b10: byte_enable = 4'b1100;
    //       default: byte_enable = 4'b0000; // 未对齐错误
    //     endcase
    //   end
    //   MEM_W: begin
    //     // 字访问: 使能全部4字节
    //     byte_enable = 4'b1111;
    //   end
    //   MEM_BU: byte_enable = ...; // 同MEM_B
    //   MEM_HU: byte_enable = ...; // 同MEM_H
    //   default: byte_enable = 4'b0000;
    // endcase
  end

  // ==========================================================================
  // Store数据对齐 (data_align - 写方向)
  // ==========================================================================
  // 根据地址低位将写数据对齐到对应字节位置
  // 例如: SB x1, 1(x0) 时，数据需要对齐到字节1位置
  // TODO: always_comb begin
  //   wdata_aligned = mem_wdata_q;
  //   case (addr_offset)
  //     2'b00: wdata_aligned = {24'b0, mem_wdata_q[7:0]};        // 字节0
  //     2'b01: wdata_aligned = {16'b0, mem_wdata_q[7:0], 8'b0};  // 字节1
  //     2'b10: wdata_aligned = {8'b0, mem_wdata_q[7:0], 16'b0};  // 字节2
  //     2'b11: wdata_aligned = {mem_wdata_q[7:0], 24'b0};        // 字节3
  //   endcase
  //
  //   // 半字对齐
  //   if (mem_size_q == MEM_H || mem_size_q == MEM_HU) begin
  //     case (addr_offset)
  //       2'b00: wdata_aligned = {16'b0, mem_wdata_q[15:0]};     // 半字0
  //       2'b10: wdata_aligned = {mem_wdata_q[15:0], 16'b0};     // 半字1
  //     endcase
  //   end
  //
  //   // 字对齐: 直接使用
  //   if (mem_size_q == MEM_W) begin
  //     wdata_aligned = mem_wdata_q;
  //   end
  // end

  // ==========================================================================
  // Load数据对齐与符号扩展 (data_align - 读方向)
  // ==========================================================================
  // 根据地址低位和访问大小提取对应字节/半字，并进行符号扩展
  // TODO: always_comb begin
  //   rdata_aligned = mem_rdata_i;
  //   case (mem_size_q)
  //     MEM_B: begin
  //       // 字节加载 + 符号扩展
  //       case (addr_offset)
  //         2'b00: rdata_aligned = {{24{mem_rdata_i[7]}},  mem_rdata_i[7:0]};
  //         2'b01: rdata_aligned = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]};
  //         2'b10: rdata_aligned = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]};
  //         2'b11: rdata_aligned = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]};
  //       endcase
  //     end
  //     MEM_BU: begin
  //       // 字节加载 + 零扩展
  //       case (addr_offset)
  //         2'b00: rdata_aligned = {24'b0, mem_rdata_i[7:0]};
  //         2'b01: rdata_aligned = {24'b0, mem_rdata_i[15:8]};
  //         2'b10: rdata_aligned = {24'b0, mem_rdata_i[23:16]};
  //         2'b11: rdata_aligned = {24'b0, mem_rdata_i[31:24]};
  //       endcase
  //     end
  //     MEM_H: begin
  //       // 半字加载 + 符号扩展
  //       case (addr_offset)
  //         2'b00: rdata_aligned = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
  //         2'b10: rdata_aligned = {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]};
  //       endcase
  //     end
  //     MEM_HU: begin
  //       // 半字加载 + 零扩展
  //       case (addr_offset)
  //         2'b00: rdata_aligned = {16'b0, mem_rdata_i[15:0]};
  //         2'b10: rdata_aligned = {16'b0, mem_rdata_i[31:16]};
  //       endcase
  //     end
  //     MEM_W: begin
  //       // 字加载: 直接使用
  //       rdata_aligned = mem_rdata_i;
  //     end
  //     default: rdata_aligned = mem_rdata_i;
  //   endcase
  // end

  // ==========================================================================
  // 内存请求控制 (lsu_ctrl)
  // ==========================================================================
  // TODO: 生成内存请求和握手信号
  // assign mem_req_o   = mem_req_q & instr_valid_q;
  // assign mem_addr_o  = alu_result_q;
  // assign mem_wdata_o = wdata_aligned;
  // assign mem_we_o    = mem_we_q;
  // assign mem_be_o    = byte_enable;

  // ==========================================================================
  // 地址对齐检查
  // ==========================================================================
  // TODO: 检测地址未对齐错误
  // assign load_err_o  = mem_req_q & ~mem_we_q & (addr_offset != 2'b00) &
  //                     (mem_size_q == MEM_W);
  // assign store_err_o = mem_req_q & mem_we_q & (addr_offset != 2'b00) &
  //                     (mem_size_q == MEM_W);

  // ==========================================================================
  // 输出到WB阶段
  // ==========================================================================
  // TODO: assign alu_result_o  = alu_result_q;
  // TODO: assign mem_rdata_o    = rdata_aligned;
  // TODO: assign pc4_o          = pc4_q;
  // TODO: assign rd_addr_o      = rd_addr_q;
  // TODO: assign rf_we_o        = rf_we_q & instr_valid_q & ~flush_i;
  // TODO: assign wb_src_o       = wb_src_q;
  // TODO: assign instr_valid_o  = instr_valid_q;

endmodule
