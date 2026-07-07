// =============================================================================
// rvp_uart.sv — RVP 简化 UART 发送器
// =============================================================================
// 功能：通过串口发送字节到电脑终端（TX only，不含接收）
//
// 寄存器映射：
//   偏移 0x00: TXDATA (W) — 写入一个字节即启动发送
//   偏移 0x04: TXSTAT (R) — bit[0]: tx_busy (1=正在发送, 0=空闲)
//
// 参数：
//   CLK_FREQ : 输入时钟频率（Hz），默认 100MHz
//   BAUD_RATE: 波特率，默认 115200
//   分频系数 = CLK_FREQ / BAUD_RATE（100MHz / 115200 ≈ 868）
//
// 接口：
//   clk_i, rst_ni : 时钟和复位
//   addr_i[3:0]   : 寄存器偏移（字节地址，只用低 4 位）
//   read_i        : 读使能
//   write_i       : 写使能
//   wdata_i       : 写数据（只取低 8 位）
//   rdata_o       : 读返回数据
//   tx_o          : 串口 TX 输出引脚（接 FPGA 的 TX 引脚）
// =============================================================================

module rvp_uart #(
  parameter int CLK_FREQ  = 100_000_000,  // 100 MHz
  parameter int BAUD_RATE = 115_200       // 115200 baud
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // 总线接口
  input  logic [31:0] addr_i,
  input  logic        read_i,
  input  logic        write_i,
  input  logic [31:0] wdata_i,
  output logic [31:0] rdata_o,

  // 物理引脚
  output logic        tx_o
);

  // 分频系数
  localparam int DIVISOR = CLK_FREQ / BAUD_RATE;

  // 发送状态机
  typedef enum logic [1:0] {
    IDLE  = 2'd0,  // 空闲，TX=1
    START = 2'd1,  // 发起始位 TX=0
    DATA  = 2'd2,  // 发 8 位数据
    STOP  = 2'd3   // 发停止位 TX=1
  } state_e;

  state_e state;
  logic [31:0] clk_div;     // 时钟分频计数器
  logic [2:0]  bit_idx;     // 当前发送的 bit 编号 (0~7)
  logic [7:0]  tx_shift;    // 发送移位寄存器
  logic        tx_busy;     // 发送忙标志

  // -------------------------------------------------------------------------
  // 寄存器写入：写 TXDATA 启动发送
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state    <= IDLE;
      clk_div  <= 0;
      bit_idx  <= 0;
      tx_shift <= 0;
      tx_busy  <= 1'b0;
    end else begin
      // 写 TXDATA 启动发送（仅在空闲时接受）
      if (write_i && addr_i[3:0] == 4'h0 && !tx_busy) begin
        tx_shift <= wdata_i[7:0];
        tx_busy  <= 1'b1;
        state    <= START;
        clk_div  <= 0;
      end else begin
        // 状态机
        unique case (state)
          IDLE: begin
            tx_busy <= 1'b0;
          end
          START: begin
            // 起始位保持一个波特周期
            if (clk_div == DIVISOR - 1) begin
              clk_div <= 0;
              state   <= DATA;
              bit_idx <= 0;
            end else begin
              clk_div <= clk_div + 1;
            end
          end
          DATA: begin
            // 逐位发送
            if (clk_div == DIVISOR - 1) begin
              clk_div  <= 0;
              tx_shift <= tx_shift >> 1;  // 右移，LSB 先发
              if (bit_idx == 3'd7) begin
                state <= STOP;
              end else begin
                bit_idx <= bit_idx + 1;
              end
            end else begin
              clk_div <= clk_div + 1;
            end
          end
          STOP: begin
            // 停止位
            if (clk_div == DIVISOR - 1) begin
              clk_div <= 0;
              state   <= IDLE;
              tx_busy <= 1'b0;
            end else begin
              clk_div <= clk_div + 1;
            end
          end
          default: state <= IDLE;
        endcase
      end
    end
  end

  // -------------------------------------------------------------------------
  // TX 输出
  // -------------------------------------------------------------------------
  always_comb begin
    unique case (state)
      IDLE:  tx_o = 1'b1;   // 空闲时 TX 为高
      START: tx_o = 1'b0;   // 起始位为低
      DATA:  tx_o = tx_shift[0];  // 数据位（LSB first）
      STOP:  tx_o = 1'b1;   // 停止位为高
      default: tx_o = 1'b1;
    endcase
  end

  // -------------------------------------------------------------------------
  // 寄存器读取
  // -------------------------------------------------------------------------
  always_comb begin
    rdata_o = 32'b0;
    if (read_i) begin
      unique case (addr_i[3:0])
        4'h4:    rdata_o = {31'b0, tx_busy};  // TXSTAT
        default: rdata_o = 32'b0;
      endcase
    end
  end

endmodule : rvp_uart
