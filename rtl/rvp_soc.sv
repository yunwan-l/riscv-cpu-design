// =============================================================================
// rvp_soc.sv — RVP 片上系统顶层
// =============================================================================
// 把 CPU 核心 + 数据 RAM + 外设（UART/GPIO/Timer）通过总线互连组成完整 SoC。
//
// 地址映射：
//   0x0000_0000 ~ 0x0000_FFFF  Data RAM   (64KB, 16K 字)
//   0x1000_0000 ~ 0x1000_FFFF  UART       (TXDATA/TXSTAT)
//   0x1001_0000 ~ 0x1001_FFFF  GPIO       (OUTPUT/INPUT)
//   0x1002_0000 ~ 0x1002_FFFF  Timer      (COUNT/CTRL)
//
// 总线协议：简单同步写 + 异步读（和 data_mem 一致）
//   - 外设建议用 lw/sw 访问（字对齐）
//   - UART 的 TXDATA 可用 sb（只取低 8 位）
//
// FPGA 引脚：
//   clk_i     : 板载时钟（NEXYS4 为 100MHz）
//   rst_ni    : 复位按钮（低有效）
//   uart_tx_o : 串口发送（接 USB-UART 的 TXD）
//   led_o     : LED 灯
//   sw_i      : 拨码开关
// =============================================================================

module rvp_soc (
  input  logic        clk_i,
  input  logic        rst_ni,

  // UART 物理引脚
  output logic        uart_tx_o,

  // GPIO 物理引脚
  output logic [15:0] led_o,
  input  logic [15:0] sw_i,

  // 调试输出（仿真/调试用）
  output logic [31:0] pc_dbg_o
);

  import rvp_pkg::*;

  // =========================================================================
  // CPU 数据总线信号
  // =========================================================================
  logic [31:0]    dbus_addr;
  logic           dbus_read, dbus_write;
  mem_size_e      dbus_size;
  logic           dbus_unsigned;
  logic [31:0]    dbus_wdata;
  logic [31:0]    dbus_rdata;

  // =========================================================================
  // 地址译码：根据地址高 16 位选择外设
  // =========================================================================
  logic is_ram, is_uart, is_gpio, is_timer;

  assign is_ram   = (dbus_addr[31:16] == 16'h0000);
  assign is_uart  = (dbus_addr[31:16] == 16'h1000);
  assign is_gpio  = (dbus_addr[31:16] == 16'h1001);
  assign is_timer = (dbus_addr[31:16] == 16'h1002);

  // 各外设的读数据
  logic [31:0] ram_rdata, uart_rdata, gpio_rdata, timer_rdata;

  // =========================================================================
  // 读数据多路选择
  // =========================================================================
  // RAM 支持子字访问（B/H/W + 符号扩展），外设按字返回
  always_comb begin
    unique case (dbus_addr[31:16])
      16'h0000:  dbus_rdata = ram_rdata;     // RAM
      16'h1000:  dbus_rdata = uart_rdata;    // UART
      16'h1001:  dbus_rdata = gpio_rdata;    // GPIO
      16'h1002:  dbus_rdata = timer_rdata;   // Timer
      default:   dbus_rdata = 32'b0;          // 未映射地址返回 0
    endcase
  end

  // =========================================================================
  // CPU 核心
  // =========================================================================
  rvp_core_pipeline cpu (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .pc_o           (pc_dbg_o),
    .instr_o        (),
    .illegal_o      (),
    .dbus_addr_o    (dbus_addr),
    .dbus_read_o    (dbus_read),
    .dbus_write_o   (dbus_write),
    .dbus_size_o    (dbus_size),
    .dbus_unsigned_o(dbus_unsigned),
    .dbus_wdata_o   (dbus_wdata),
    .dbus_rdata_i   (dbus_rdata)
  );

  // =========================================================================
  // Data RAM（8KB，DEPTH=2048 → ADDR_BITS=11 → 13位地址）
  // =========================================================================
  rvp_data_mem ram (
    .clk_i         (clk_i),
    .addr_i        (dbus_addr[12:0]),
    .write_data_i  (dbus_wdata),
    .mem_read_i    (dbus_read  && is_ram),
    .mem_write_i   (dbus_write && is_ram),
    .mem_size_i    (dbus_size),
    .mem_unsigned_i(dbus_unsigned),
    .read_data_o   (ram_rdata)
  );

  // =========================================================================
  // UART 发送器
  // =========================================================================
  rvp_uart uart (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .addr_i  (dbus_addr[3:0]),
    .read_i  (dbus_read  && is_uart),
    .write_i (dbus_write && is_uart),
    .wdata_i (dbus_wdata[7:0]),
    .rdata_o (uart_rdata),
    .tx_o    (uart_tx_o)
  );

  // =========================================================================
  // GPIO
  // =========================================================================
  rvp_gpio gpio (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .addr_i  (dbus_addr[3:0]),
    .read_i  (dbus_read  && is_gpio),
    .write_i (dbus_write && is_gpio),
    .wdata_i (dbus_wdata[15:0]),
    .rdata_o (gpio_rdata),
    .led_o   (led_o),
    .sw_i    (sw_i)
  );

  // =========================================================================
  // Timer
  // =========================================================================
  rvp_timer timer (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .addr_i  (dbus_addr[3:0]),
    .read_i  (dbus_read  && is_timer),
    .write_i (dbus_write && is_timer),
    .wdata_i (dbus_wdata[1:0]),
    .rdata_o (timer_rdata)
  );

endmodule : rvp_soc
