/**
 * rvp_uart.sv - UART Serial Controller
 *
 * RVP处理器的UART串口控制器模块，兼容16550 UART寄存器映射的子集。
 * 提供TX/RX FIFO、波特率生成和中断支持。
 *
 * 参考: 16550 UART (PC16550D) 寄存器映射
 *
 * 功能:
 *   - 可编程波特率生成 (CLOCK_FREQ / BAUD_RATE)
 *   - TX发送: 8位数据位，1位停止位，无校验
 *   - RX接收: 8位数据位，1位停止位，无校验
 *   - TX/RX FIFO缓冲 (深度可配置)
 *   - 内存映射寄存器接口
 *   - TX空中断和RX数据可用中断
 *
 * 寄存器映射 (偏移地址):
 *   0x00: RBR (读) - 接收缓冲寄存器 / THR (写) - 发送保持寄存器
 *   0x04: IER      - 中断使能寄存器
 *   0x08: IIR (读) - 中断识别 / FCR (写) - FIFO控制寄存器
 *   0x0C: LCR      - 线路控制寄存器
 *   0x10: LSR (只读) - 线路状态寄存器
 *
 * 寄存器位定义:
 *   IER[0] = RX数据可用中断使能
 *   IER[1] = TX空中断使能
 *   LSR[0] = RX数据就绪 (DR)
 *   LSR[1] = 溢出错误 (OE)
 *   LSR[5] = THR空 (THRE)
 *   LSR[6] = 发送器空 (TEMT)
 */

`include "rvp_config.svh"

module rvp_uart #(
    /// 输入时钟频率 (Hz)。默认100MHz
    parameter int unsigned CLOCK_FREQ = 100_000_000,
    /// 波特率。默认115200
    parameter int unsigned BAUD_RATE  = 115200,
    /// FIFO深度 (字节数)。默认16
    parameter int         FIFO_DEPTH  = 16
) (
    input  logic         clk_i,            // 时钟
    input  logic         rst_ni,           // 异步低有效复位

    // ==========================================================================
    // UART物理接口
    // ==========================================================================
    input  logic         rx_i,             // 串行接收输入
    output logic         tx_o,             // 串行发送输出

    // ==========================================================================
    // 总线接口 (内存映射)
    // ==========================================================================
    input  logic         bus_req_i,        // 总线请求
    input  logic [31:0]  bus_addr_i,       // 总线地址 (字节地址)
    input  logic         bus_we_i,         // 总线写使能
    input  logic [31:0]  bus_wdata_i,      // 总线写数据
    output logic [31:0]  bus_rdata_o,      // 总线读数据
    output logic         bus_rvalid_o,     // 总线读有效

    // ==========================================================================
    // 中断输出
    // ==========================================================================
    output logic         irq_tx_o,         // TX空中断
    output logic         irq_rx_o          // RX数据可用中断
);

  // ==========================================================================
  // 本地参数
  // ==========================================================================

  // 波特率分频系数 = CLOCK_FREQ / BAUD_RATE
  localparam int unsigned CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;

  // 地址位宽 (用于寄存器选择)
  localparam int ADDR_LSB = 4;  // 寄存器地址偏移位宽 (16字节空间)

  // ==========================================================================
  // 寄存器偏移地址定义
  // ==========================================================================

  localparam logic [ADDR_LSB-1:0] REG_RBR_THR = 4'h0;  // 0x00: RBR(读)/THR(写)
  localparam logic [ADDR_LSB-1:0] REG_IER     = 4'h4;  // 0x04: IER
  localparam logic [ADDR_LSB-1:0] REG_IIR_FCR = 4'h8;  // 0x08: IIR(读)/FCR(写)
  localparam logic [ADDR_LSB-1:0] REG_LCR     = 4'hC;  // 0x0C: LCR
  localparam logic [ADDR_LSB-1:0] REG_LSR     = 4'h10; // 0x10: LSR

  // ==========================================================================
  // 寄存器存储
  // ==========================================================================

  // IER: 中断使能寄存器
  logic        ier_rx_enable;   // IER[0]: RX数据可用中断使能
  logic        ier_tx_enable;    // IER[1]: TX空中断使能

  // LCR: 线路控制寄存器 (简化版)
  logic [7:0]  lcr_reg;         // LCR寄存器值

  // FCR: FIFO控制寄存器
  logic        fcr_enable;       // FIFO使能
  logic        fcr_clear_rx;     // 清除RX FIFO
  logic        fcr_clear_tx;     // 清除TX FIFO

  // ==========================================================================
  // 线路状态寄存器 (LSR) 各位
  // ==========================================================================

  logic        lsr_dr;           // LSR[0]: 数据就绪 (Data Ready)
  logic        lsr_oe;           // LSR[1]: 溢出错误 (Overrun Error)
  logic        lsr_thre;         // LSR[5]: THR空 (Transmit Holding Register Empty)
  logic        lsr_temt;         // LSR[6]: 发送器空 (Transmitter Empty)

  // ==========================================================================
  // 波特率生成器
  // ==========================================================================

  logic [31:0] baud_counter;     // 波特率计数器
  logic        baud_tick;         // 波特率采样脉冲

  // ==========================================================================
  // TX发送逻辑
  // ==========================================================================

  // TX FIFO信号
  logic        tx_fifo_write;    // TX FIFO写使能
  logic        tx_fifo_read;     // TX FIFO读使能
  logic        tx_fifo_full;     // TX FIFO满
  logic        tx_fifo_empty;    // TX FIFO空
  logic [7:0]  tx_fifo_rdata;    // TX FIFO读数据

  // TX发送状态机
  typedef enum logic [2:0] {
    TX_IDLE    = 3'd0,  // 空闲
    TX_START   = 3'd1,  // 发送起始位
    TX_DATA    = 3'd2,  // 发送数据位
    TX_STOP    = 3'd3,  // 发送停止位
    TX_DONE    = 3'd4   // 发送完成
  } tx_state_e;

  tx_state_e   tx_state;         // TX状态机当前状态
  logic [15:0] tx_clk_div;        // TX位时钟分频计数器
  logic [3:0]  tx_bit_idx;       // TX数据位索引
  logic [7:0]  tx_shift_reg;     // TX移位寄存器

  // ==========================================================================
  // RX接收逻辑
  // ==========================================================================

  // RX FIFO信号
  logic        rx_fifo_write;    // RX FIFO写使能
  logic        rx_fifo_full;     // RX FIFO满
  logic        rx_fifo_empty;    // RX FIFO空
  logic [7:0]  rx_fifo_rdata;    // RX FIFO读数据

  // RX接收状态机
  typedef enum logic [2:0] {
    RX_IDLE    = 3'd0,  // 空闲
    RX_START   = 3'd1,  // 检测起始位
    RX_DATA    = 3'd2,  // 接收数据位
    RX_STOP    = 3'd3,  // 接收停止位
    RX_DONE    = 3'd4   // 接收完成
  } rx_state_e;

  rx_state_e   rx_state;         // RX状态机当前状态
  logic [15:0] rx_clk_div;       // RX位时钟分频计数器
  logic [3:0]  rx_bit_idx;      // RX数据位索引
  logic [7:0]  rx_shift_reg;    // RX移位寄存器
  logic        rx_prev;          // rx_i上一周期值 (用于边沿检测)

  // ==========================================================================
  // FIFO实例化占位 (实际使用中可实例化FIFO模块)
  // ==========================================================================

  // TODO: 实例化TX FIFO
  // rvp_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) tx_fifo (
  //   .clk_i(clk_i), .rst_ni(rst_ni),
  //   .write_i(tx_fifo_write), .read_i(tx_fifo_read),
  //   .wdata_i(bus_wdata_i[7:0]),
  //   .rdata_o(tx_fifo_rdata),
  //   .full_o(tx_fifo_full), .empty_o(tx_fifo_empty)
  // );

  // TODO: 实例化RX FIFO
  // rvp_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) rx_fifo (
  //   .clk_i(clk_i), .rst_ni(rst_ni),
  //   .write_i(rx_fifo_write), .read_i(rx_fifo_read),
  //   .wdata_i(rx_shift_reg),
  //   .rdata_o(rx_fifo_rdata),
  //   .full_o(rx_fifo_full), .empty_o(rx_fifo_empty)
  // );

  // ==========================================================================
  // 寄存器写逻辑
  // ==========================================================================

  // 总线地址解码 (取低4位)
  logic [ADDR_LSB-1:0] reg_addr;
  assign reg_addr = bus_addr_i[ADDR_LSB-1:0];

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      ier_rx_enable <= 1'b0;
      ier_tx_enable <= 1'b0;
      lcr_reg       <= 8'h03;  // 默认8N1
      fcr_enable    <= 1'b0;
      // TODO: 初始化其他寄存器
    end else if (bus_req_i && bus_we_i) begin
      unique case (reg_addr)
        REG_RBR_THR: begin
          // THR写入: 触发TX FIFO写入
          // TODO: tx_fifo_write <= 1'b1;
        end
        REG_IER: begin
          ier_rx_enable <= bus_wdata_i[0];
          ier_tx_enable <= bus_wdata_i[1];
          // TODO: 处理其他IER位
        end
        REG_IIR_FCR: begin
          // FCR写入
          fcr_enable    <= bus_wdata_i[0];
          // TODO: fcr_clear_rx, fcr_clear_tx 处理
        end
        REG_LCR: begin
          lcr_reg <= bus_wdata_i[7:0];
        end
        default: ; // 无操作
      endcase
    end
  end

  // ==========================================================================
  // 寄存器读逻辑
  // ==========================================================================

  logic [31:0] rdata_q;

  always_comb begin
    rdata_q = 32'h0;
    unique case (reg_addr)
      REG_RBR_THR: begin
        // 读RBR: 从RX FIFO读取
        // TODO: rdata_q = {24'h0, rx_fifo_rdata};
      end
      REG_IER: begin
        rdata_q = {30'h0, ier_tx_enable, ier_rx_enable};
      end
      REG_IIR_FCR: begin
        // IIR读取: 中断识别
        // TODO: 返回中断ID
      end
      REG_LCR: begin
        rdata_q = {24'h0, lcr_reg};
      end
      REG_LSR: begin
        // LSR读取
        rdata_q = {
          25'h0,
          lsr_temt,     // [6]
          lsr_thre,     // [5]
          3'h0,         // [4:2] 保留/错误标志
          lsr_oe,       // [1]
          lsr_dr        // [0]
        };
      end
      default: rdata_q = 32'h0;
    endcase
  end

  // 读有效信号 (1周期延迟)
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      bus_rvalid_o <= 1'b0;
    end else begin
      bus_rvalid_o <= bus_req_i;
    end
  end

  assign bus_rdata_o = rdata_q;

  // ==========================================================================
  // 波特率生成器
  // ==========================================================================

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      baud_counter <= 32'h0;
      baud_tick    <= 1'b0;
    end else begin
      if (baud_counter >= CLKS_PER_BIT - 1) begin
        baud_counter <= 32'h0;
        baud_tick    <= 1'b1;
      end else begin
        baud_counter <= baud_counter + 1;
        baud_tick    <= 1'b0;
      end
    end
  end

  // ==========================================================================
  // TX发送状态机
  // ==========================================================================

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      tx_state      <= TX_IDLE;
      tx_clk_div    <= 16'h0;
      tx_bit_idx    <= 4'h0;
      tx_shift_reg  <= 8'h0;
      tx_o          <= 1'b1;      // 空闲状态为高
      tx_fifo_read  <= 1'b0;
      // TODO: 初始化TX相关信号
    end else begin
      tx_fifo_read <= 1'b0;  // 默认不读
      unique case (tx_state)
        TX_IDLE: begin
          tx_o <= 1'b1;  // 空闲高电平
          // TODO: 检查TX FIFO是否有数据
          // if (!tx_fifo_empty) begin
          //   tx_shift_reg <= tx_fifo_rdata;
          //   tx_fifo_read <= 1'b1;
          //   tx_state <= TX_START;
          //   tx_clk_div <= 0;
          // end
        end
        TX_START: begin
          tx_o <= 1'b0;  // 发送起始位(低)
          // TODO: 等待一个波特周期
          // if (tx_clk_div >= CLKS_PER_BIT - 1) begin
          //   tx_clk_div <= 0;
          //   tx_state <= TX_DATA;
          //   tx_bit_idx <= 0;
          // end else begin
          //   tx_clk_div <= tx_clk_div + 1;
          // end
        end
        TX_DATA: begin
          tx_o <= tx_shift_reg[tx_bit_idx];
          // TODO: 发送8个数据位
          // if (tx_clk_div >= CLKS_PER_BIT - 1) begin
          //   tx_clk_div <= 0;
          //   if (tx_bit_idx == 7) begin
          //     tx_state <= TX_STOP;
          //   end else begin
          //     tx_bit_idx <= tx_bit_idx + 1;
          //   end
          // end else begin
          //   tx_clk_div <= tx_clk_div + 1;
          // end
        end
        TX_STOP: begin
          tx_o <= 1'b1;  // 发送停止位(高)
          // TODO: 等待一个波特周期后回到IDLE
        end
        TX_DONE: begin
          tx_state <= TX_IDLE;
        end
        default: tx_state <= TX_IDLE;
      endcase
    end
  end

  // ==========================================================================
  // RX接收状态机
  // ==========================================================================

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      rx_state      <= RX_IDLE;
      rx_clk_div    <= 16'h0;
      rx_bit_idx    <= 4'h0;
      rx_shift_reg  <= 8'h0;
      rx_prev       <= 1'b1;
      rx_fifo_write <= 1'b0;
      lsr_dr        <= 1'b0;
      lsr_oe        <= 1'b0;
      // TODO: 初始化RX相关信号
    end else begin
      rx_fifo_write <= 1'b0;  // 默认不写
      rx_prev       <= rx_i;
      unique case (rx_state)
        RX_IDLE: begin
          // TODO: 检测下降沿 (起始位)
          // if (rx_prev && !rx_i) begin
          //   rx_state <= RX_START;
          //   rx_clk_div <= 0;
          // end
        end
        RX_START: begin
          // TODO: 在半波特周期时验证起始位
          // if (rx_clk_div == (CLKS_PER_BIT-1)/2) begin
          //   if (!rx_i) begin // 确认起始位
          //     rx_clk_div <= 0;
          //     rx_state <= RX_DATA;
          //     rx_bit_idx <= 0;
          //   end else begin
          //     rx_state <= RX_IDLE; // 假起始位
          //   end
          // end else begin
          //   rx_clk_div <= rx_clk_div + 1;
          // end
        end
        RX_DATA: begin
          // TODO: 在每个波特周期中心采样数据位
          // if (rx_clk_div >= CLKS_PER_BIT - 1) begin
          //   rx_clk_div <= 0;
          //   rx_shift_reg[rx_bit_idx] <= rx_i;
          //   if (rx_bit_idx == 7) begin
          //     rx_state <= RX_STOP;
          //   end else begin
          //     rx_bit_idx <= rx_bit_idx + 1;
          //   end
          // end else begin
          //   rx_clk_div <= rx_clk_div + 1;
          // end
        end
        RX_STOP: begin
          // TODO: 检测停止位，写入RX FIFO
          // if (rx_clk_div >= CLKS_PER_BIT - 1) begin
          //   rx_fifo_write <= 1'b1;
          //   rx_state <= RX_IDLE;
          // end else begin
          //   rx_clk_div <= rx_clk_div + 1;
          // end
        end
        default: rx_state <= RX_IDLE;
      endcase
    end
  end

  // ==========================================================================
  // 线路状态寄存器更新
  // ==========================================================================

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      lsr_thre <= 1'b1;  // 复位后THR为空
      lsr_temt <= 1'b1;  // 复位后发送器为空
    end else begin
      // TODO: 更新LSR状态
      // lsr_thre <= tx_fifo_empty;
      // lsr_temt <= tx_fifo_empty && (tx_state == TX_IDLE);
      // lsr_dr   <= !rx_fifo_empty;
      // lsr_oe   <= rx_fifo_full && rx_fifo_write;  // FIFO满时仍有新数据
    end
  end

  // ==========================================================================
  // 中断生成
  // ==========================================================================

  always_comb begin
    // TX空中断: THRE为空且IER TX中断使能
    irq_tx_o = ier_tx_enable && lsr_thre;
    // RX数据可用中断: DR为1且IER RX中断使能
    irq_rx_o = ier_rx_enable && lsr_dr;
    // TODO: 添加更多中断条件 (溢出错误、帧错误等)
  end

  // ==========================================================================
  // 未使用信号
  // ==========================================================================

  // 消除未使用警告
  logic _unused;
  assign _unused = baud_tick;

endmodule
