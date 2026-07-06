/**
 * rvp_register_file.sv - RVP Register File
 *
 * 寄存器堆实现，支持2读1写操作，面向FPGA BRAM优化。
 * 参考ibex_register_file_fpga.sv的设计。
 *
 * 特性:
 *   - 32个32位寄存器 (RV32I) 或 16个 (RV32E)
 *   - x0硬连线为0，写入x0被忽略
 *   - 2个独立读端口 (rs1, rs2)
 *   - 1个写端口 (rd)
 *   - 同步写，异步读
 *   - FPGA BRAM推断优化 (Xilinx RAM32M)
 *   - 无写读转发 (write-after-read forwarding)
 *   - 初始化为0
 *
 * 注意: 此实现不做写读转发，需要依靠前递单元或stall来处理
 *       写后读冒险。
 */

`include "rvp_config.svh"

module rvp_register_file import rvp_pkg::*; #(
    parameter bit          RV32E       = 1'b0,     // 1=RVA32E (16 regs), 0=RV32I (32 regs)
    parameter int unsigned DataWidth   = REG_DATA_W, // 数据宽度
    parameter bit          DummyInstr  = 1'b0        // 伪指令支持
) (
    input  logic                      clk_i,        // 时钟
    input  logic                      rst_ni,       // 异步低复位

    // 测试与安全相关
    input  logic                      test_en_i,    // 测试使能(扫描)
    input  logic                      dummy_instr_id_i, // ID阶段伪指令标志
    input  logic                      dummy_instr_wb_i, // WB阶段伪指令标志

    // 读端口1 (rs1)
    input  logic [REG_ADDR_W-1:0]    raddr_a_i,    // 读地址A (rs1)
    output logic [DataWidth-1:0]      rdata_a_o,    // 读数据A

    // 读端口2 (rs2)
    input  logic [REG_ADDR_W-1:0]    raddr_b_i,    // 读地址B (rs2)
    output logic [DataWidth-1:0]      rdata_b_o,    // 读数据B

    // 写端口1 (rd)
    input  logic [REG_ADDR_W-1:0]    waddr_a_i,    // 写地址A (rd)
    input  logic [DataWidth-1:0]      wdata_a_i,    // 写数据A
    input  logic                      we_a_i        // 写使能A
);

  import rvp_pkg::*;

  // ==========================================================================
  // 参数计算
  // ==========================================================================

  // 地址宽度: RV32E=4位(16寄存器), RV32I=5位(32寄存器)
  localparam int unsigned ADDR_WIDTH  = RV32E ? 4 : 5;
  localparam int unsigned NUM_WORDS   = 2 ** ADDR_WIDTH;

  // 零值常量 (用于x0和初始化)
  localparam logic [DataWidth-1:0] WORD_ZERO = '0;

  // ==========================================================================
  // 寄存器存储阵列
  // ==========================================================================

  // 寄存器存储阵列 - 综合工具会推断为BRAM
  logic [DataWidth-1:0] mem [NUM_WORDS];

  // 写使能: 写入x0时忽略
  logic we;

  // 读数据中间信号 (用于x0检测)
  logic [DataWidth-1:0] mem_out_a;
  logic [DataWidth-1:0] mem_out_b;

  // ==========================================================================
  // 写端口逻辑
  // ==========================================================================

  // 写使能门控: x0不可写
  // 当写地址为0时，强制禁能写操作
  // TODO: assign we = (waddr_a_i == '0) ? 1'b0 : we_a_i;

  // 同步写过程
  // 使用always而非always_ff以支持BRAM的initial初始化
  // 参考: ibex_register_file_fpga.sv
  // TODO:
  // always @(posedge clk_i) begin : sync_write
  //   if (we == 1'b1) begin
  //     mem[waddr_a_i] <= wdata_a_i;
  //   end
  // end : sync_write

  // ==========================================================================
  // BRAM初始化
  // ==========================================================================

  // 初始化所有寄存器为0值
  // 这对于FPGA上电后的确定性非常重要
  // TODO:
  // initial begin
  //   for (int k = 0; k < NUM_WORDS; k++) begin
  //     mem[k] = WORD_ZERO;
  //   end
  // end

  // ==========================================================================
  // 读端口逻辑
  // ==========================================================================

  // 读端口A: x0硬连线为0
  // TODO: assign mem_out_a = mem[raddr_a_i];
  //       assign rdata_a_o = (raddr_a_i == '0) ? WORD_ZERO : mem_out_a;

  // 读端口B: x0硬连线为0
  // TODO: assign mem_out_b = mem[raddr_b_i];
  //       assign rdata_b_o = (raddr_b_i == '0) ? WORD_ZERO : mem_out_b;

  // ==========================================================================
  // 未使用信号处理
  // ==========================================================================

  // 复位信号在此实现中未使用 (BRAM不需要复位)
  // TODO: logic unused_rst_ni;
  //       assign unused_rst_ni = rst_ni;

  // 伪指令支持在此实现中未使用
  // TODO: logic unused_dummy;
  //       assign unused_dummy = dummy_instr_id_i ^ dummy_instr_wb_i;

  // 测试使能在此实现中未使用
  // TODO: logic unused_test_en;
  //       assign unused_test_en = test_en_i;

  // ==========================================================================
  // 设计说明
  // ==========================================================================
  // 1. 本实现不包含写读转发(Write-Read Forwarding)
  //    如果同一周期内读和写同一寄存器，将读到旧值
  //    需要由前递单元(rvp_forward_unit)或冒险检测(rvp_hazard_unit)处理
  //
  // 2. 读操作是异步的(组合逻辑)
  //    写操作是同步的(时序逻辑, 上升沿)
  //
  // 3. FPGA综合时，mem会被推断为RAM32M原语(Xilinx)
  //    其他FPGA厂商可能需要调整

endmodule
