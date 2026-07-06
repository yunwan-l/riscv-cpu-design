/**
 * rvp_soc_top.sv - RVP SoC Top-Level Module
 *
 * RVP SoC的顶层集成模块，实例化CPU核心、存储器和外设，
 * 通过总线互连连接所有组件。
 *
 * 参考: ibex examples/simple_system/ibex_simple_system.sv
 *
 * 系统架构:
 *                              ┌───────────┐
 *                              │  rvp_core  │ (CPU核心)
 *                              └─────┬─────┘
 *                          ┌─────────┼─────────┐
 *                     IF总线   │   数据总线    │
 *                          ▼         ▼
 *                   ┌──────────┐ ┌──────────────┐
 *                   │ InstrMem │ │ BusInterconn │
 *                   └──────────┘ └──────┬───────┘
 *                       (直接连接)     │ 4路分发
 *                          ┌───────────┼───────────┐
 *                     ┌─────┼─────┐ ┌────┼───┐ ┌────┼────┐
 *                     ▼     ▼     ▼ ▼        ▼ ▼        ▼
 *                  DataMem  UART  GPIO     Timer
 *
 * 地址映射:
 *   0x0000_0000 - 0x0000_7FFF  指令存储器 (32KB)
 *   0x0001_0000 - 0x0001_7FFF  数据存储器 (32KB)
 *   0x1000_0000 - 0x1000_0FFF  UART
 *   0x1001_0000 - 0x1001_0FFF  GPIO
 *   0x1002_0000 - 0x1002_0FFF  Timer
 *
 * 外部接口:
 *   - 时钟和复位
 *   - UART TX/RX引脚
 *   - GPIO输入/输出引脚
 */

`include "rvp_config.svh"

module rvp_soc_top import rvp_pkg::*; #(
    // ==========================================================================
    // CPU核心参数
    // ==========================================================================
    parameter bit          RV32E          = `RVP_RV32E,       // RV32E(16 regs) or RV32I(32 regs)
    parameter bit          RV32M          = `RVP_RV32M,        // M扩展使能
    parameter bit          RV32C          = `RVP_RV32C,        // C扩展使能
    parameter int unsigned PipelineStages  = `RVP_PIPELINE_STAGES,
    parameter bit          WritebackStage  = `RVP_WRITEBACK_STAGE,
    parameter bit          Forwarding      = `RVP_FORWARDING,

    // ==========================================================================
    // 存储器参数
    // ==========================================================================
    parameter int         InstrMemDepth  = `RVP_INSTR_MEM_SIZE / 4,  // 指令存储器深度(字)
    parameter int         DataMemDepth    = `RVP_DATA_MEM_SIZE / 4,   // 数据存储器深度(字)
    parameter             SRAMInitFile    = "",                       // 固件初始化文件

    // ==========================================================================
    // 外设参数
    // ==========================================================================
    parameter int unsigned ClockFreq      = 100_000_000,  // 时钟频率
    parameter int unsigned UartBaudRate   = `RVP_UART_BAUD,// UART波特率
    parameter int         GpioWidth      = `RVP_GPIO_WIDTH // GPIO宽度
) (
    input  logic                 clk_i,          // 系统时钟
    input  logic                 rst_ni,         // 异步低有效复位

    // ==========================================================================
    // UART接口
    // ==========================================================================
    input  logic                 uart_rx_i,      // UART接收
    output logic                 uart_tx_o,      // UART发送

    // ==========================================================================
    // GPIO接口
    // ==========================================================================
    input  logic [GpioWidth-1:0] gpio_in_i,     // GPIO输入
    output logic [GpioWidth-1:0] gpio_out_o      // GPIO输出
);

  // ==========================================================================
  // 总线设备枚举定义
  // ==========================================================================

  // 数据总线从设备 (CPU数据端口连接)
  typedef enum logic [2:0] {
    DEV_DATA_MEM = 3'd0,  // 数据存储器
    DEV_UART     = 3'd1,  // UART
    DEV_GPIO     = 3'd2,  // GPIO
    DEV_TIMER    = 3'd3   // 定时器
  } bus_device_e;

  // 总线主机 (CPU数据端口)
  typedef enum logic {
    HOST_CORE_D = 1'd0   // CPU数据总线
  } bus_host_e;

  localparam int NrDevices = 4;  // 数据总线从设备数量
  localparam int NrHosts   = 1;  // 数据总线主机数量

  // ==========================================================================
  // 地址映射常量
  // ==========================================================================

  // 指令存储器: 0x0000_0000 (32KB)
  localparam logic [31:0] INSTR_MEM_BASE = 32'h0000_0000;
  localparam logic [31:0] INSTR_MEM_MASK = ~32'h0000_7FFF;  // 32KB

  // 数据存储器: 0x0001_0000 (32KB)
  localparam logic [31:0] DATA_MEM_BASE  = 32'h0001_0000;
  localparam logic [31:0] DATA_MEM_MASK  = ~32'h0000_7FFF;  // 32KB

  // UART: 0x1000_0000 (4KB)
  localparam logic [31:0] UART_BASE      = 32'h1000_0000;
  localparam logic [31:0] UART_MASK       = ~32'h0000_0FFF;  // 4KB

  // GPIO: 0x1001_0000 (4KB)
  localparam logic [31:0] GPIO_BASE      = 32'h1001_0000;
  localparam logic [31:0] GPIO_MASK       = ~32'h0000_0FFF;  // 4KB

  // Timer: 0x1002_0000 (4KB)
  localparam logic [31:0] TIMER_BASE      = 32'h1002_0000;
  localparam logic [31:0] TIMER_MASK       = ~32'h0000_0FFF;  // 4KB

  // ==========================================================================
  // CPU核心接口信号
  // ==========================================================================

  // 指令总线信号
  logic        instr_req;
  logic        instr_gnt;
  logic        instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic        instr_err;

  // 数据总线信号 (主机侧)
  logic        host_req    [NrHosts];
  logic        host_gnt    [NrHosts];
  logic [31:0] host_addr   [NrHosts];
  logic        host_we      [NrHosts];
  logic [ 3:0] host_be      [NrHosts];
  logic [31:0] host_wdata   [NrHosts];
  logic        host_rvalid  [NrHosts];
  logic [31:0] host_rdata   [NrHosts];
  logic        host_err     [NrHosts];

  // 数据总线信号 (从设备侧)
  logic        device_req    [NrDevices];
  logic [31:0] device_addr   [NrDevices];
  logic        device_we     [NrDevices];
  logic [ 3:0] device_be     [NrDevices];
  logic [31:0] device_wdata  [NrDevices];
  logic        device_rvalid [NrDevices];
  logic [31:0] device_rdata  [NrDevices];
  logic        device_err    [NrDevices];

  // 地址映射配置
  logic [31:0] cfg_device_addr_base [NrDevices];
  logic [31:0] cfg_device_addr_mask [NrDevices];

  // 中断信号
  logic        timer_irq;
  logic        uart_irq_tx;
  logic        uart_irq_rx;

  // ==========================================================================
  // 地址映射配置赋值
  // ==========================================================================

  assign cfg_device_addr_base[DEV_DATA_MEM] = DATA_MEM_BASE;
  assign cfg_device_addr_mask[DEV_DATA_MEM] = DATA_MEM_MASK;

  assign cfg_device_addr_base[DEV_UART]     = UART_BASE;
  assign cfg_device_addr_mask[DEV_UART]     = UART_MASK;

  assign cfg_device_addr_base[DEV_GPIO]    = GPIO_BASE;
  assign cfg_device_addr_mask[DEV_GPIO]    = GPIO_MASK;

  assign cfg_device_addr_base[DEV_TIMER]   = TIMER_BASE;
  assign cfg_device_addr_mask[DEV_TIMER]   = TIMER_MASK;

  // ==========================================================================
  // 指令总线直接连接 (无总线互连)
  // ==========================================================================

  // 指令存储器直接连接到CPU指令端口
  assign instr_gnt   = instr_req;     // 立即授权
  assign instr_err   = 1'b0;          // 无错误

  // ==========================================================================
  // 从设备错误信号 (内存设备无错误)
  // ==========================================================================

  assign device_err[DEV_DATA_MEM] = 1'b0;
  assign device_err[DEV_UART]     = 1'b0;
  assign device_err[DEV_GPIO]     = 1'b0;
  assign device_err[DEV_TIMER]    = 1'b0;

  // ==========================================================================
  // CPU核心实例化 (rvp_core)
  // ==========================================================================

  rvp_core #(
    .RV32E           (RV32E),
    .RV32M           (RV32M),
    .RV32C           (RV32C),
    .PipelineStages  (PipelineStages),
    .WritebackStage  (WritebackStage),
    .Forwarding      (Forwarding)
  ) u_core (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),

    .hart_id_i       (32'h0),              // Hart ID = 0
    .boot_addr_i     (INSTR_MEM_BASE),     // 启动地址 = 指令存储器基地址

    // 指令总线
    .instr_req_o     (instr_req),
    .instr_gnt_i     (instr_gnt),
    .instr_rvalid_i  (instr_rvalid),
    .instr_addr_o    (instr_addr),
    .instr_rdata_i   (instr_rdata),
    .instr_err_i     (instr_err),

    // 数据总线
    .data_req_o      (host_req[HOST_CORE_D]),
    .data_gnt_i      (host_gnt[HOST_CORE_D]),
    .data_rvalid_i   (host_rvalid[HOST_CORE_D]),
    .data_we_o       (host_we[HOST_CORE_D]),
    .data_be_o       (host_be[HOST_CORE_D]),
    .data_addr_o     (host_addr[HOST_CORE_D]),
    .data_wdata_o    (host_wdata[HOST_CORE_D]),
    .data_rdata_i    (host_rdata[HOST_CORE_D]),
    .data_err_i      (host_err[HOST_CORE_D]),

    // 中断
    .irq_software_i  (1'b0),               // 软件中断 (未使用)
    .irq_timer_i     (timer_irq),           // 定时器中断
    .irq_external_i  (1'b0),               // 外部中断 (未使用)
    .irq_fast_i      (15'b0),              // 快速中断 (未使用)
    .irq_nm_i        (1'b0),               // NMI (未使用)
    .irq_pending_o   (),                   // 中断挂起 (未连接)

    // 调试
    .debug_req_i     (1'b0),               // 调试请求 (未使用)
    .crash_dump_o    (),                   // 崩溃转储 (未连接)

    // 性能计数
    .perf_jump_o     (),                   // 跳转计数 (未连接)
    .perf_tbranch_o  ()                    // 分支计数 (未连接)
  );

  // ==========================================================================
  // 指令存储器实例化
  // ==========================================================================

  rvp_instr_mem #(
    .Depth       (InstrMemDepth),
    .MemInitFile (SRAMInitFile)
  ) u_instr_mem (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),

    .req_i       (instr_req),
    .addr_i      (instr_addr),
    .rdata_o     (instr_rdata),
    .rvalid_o    (instr_rvalid)
  );

  // ==========================================================================
  // 总线互连实例化
  // ==========================================================================

  rvp_bus_interconnect #(
    .NrDevices    (NrDevices),
    .NrHosts      (NrHosts),
    .DataWidth    (32),
    .AddressWidth (32)
  ) u_bus (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),

    // 主机端口
    .host_req_i          (host_req),
    .host_gnt_o          (host_gnt),
    .host_addr_i         (host_addr),
    .host_we_i           (host_we),
    .host_be_i           (host_be),
    .host_wdata_i        (host_wdata),
    .host_rvalid_o       (host_rvalid),
    .host_rdata_o        (host_rdata),
    .host_err_o          (host_err),

    // 从设备端口
    .device_req_o        (device_req),
    .device_addr_o       (device_addr),
    .device_we_o         (device_we),
    .device_be_o         (device_be),
    .device_wdata_o      (device_wdata),
    .device_rvalid_i     (device_rvalid),
    .device_rdata_i      (device_rdata),
    .device_err_i        (device_err),

    // 地址映射配置
    .cfg_device_addr_base (cfg_device_addr_base),
    .cfg_device_addr_mask (cfg_device_addr_mask)
  );

  // ==========================================================================
  // 数据存储器实例化
  // ==========================================================================

  rvp_data_mem #(
    .Depth       (DataMemDepth),
    .MemInitFile ("")                    // 数据存储器不预加载
  ) u_data_mem (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),

    .req_i       (device_req[DEV_DATA_MEM]),
    .we_i        (device_we[DEV_DATA_MEM]),
    .be_i        (device_be[DEV_DATA_MEM]),
    .addr_i      (device_addr[DEV_DATA_MEM]),
    .wdata_i     (device_wdata[DEV_DATA_MEM]),
    .rdata_o     (device_rdata[DEV_DATA_MEM]),
    .rvalid_o    (device_rvalid[DEV_DATA_MEM])
  );

  // ==========================================================================
  // UART实例化
  // ==========================================================================

`ifdef RVP_UART_ENABLE
  rvp_uart #(
    .CLOCK_FREQ (ClockFreq),
    .BAUD_RATE  (UartBaudRate)
  ) u_uart (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),

    // UART物理接口
    .rx_i        (uart_rx_i),
    .tx_o        (uart_tx_o),

    // 总线接口
    .bus_req_i   (device_req[DEV_UART]),
    .bus_addr_i  (device_addr[DEV_UART]),
    .bus_we_i    (device_we[DEV_UART]),
    .bus_wdata_i (device_wdata[DEV_UART]),
    .bus_rdata_o (device_rdata[DEV_UART]),
    .bus_rvalid_o(device_rvalid[DEV_UART]),

    // 中断
    .irq_tx_o    (uart_irq_tx),
    .irq_rx_o    (uart_irq_rx)
  );
`else
  // UART未使能: 输出默认值
  assign uart_tx_o             = 1'b1;
  assign device_rdata[DEV_UART] = 32'h0;
  assign device_rvalid[DEV_UART]= device_req[DEV_UART];
  assign uart_irq_tx           = 1'b0;
  assign uart_irq_rx           = 1'b0;
`endif

  // ==========================================================================
  // GPIO实例化
  // ==========================================================================

`ifdef RVP_GPIO_ENABLE
  rvp_gpio #(
    .GPIO_WIDTH (GpioWidth)
  ) u_gpio (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),

    // GPIO物理接口
    .gpio_in_i   (gpio_in_i),
    .gpio_out_o  (gpio_out_o),

    // 总线接口
    .bus_req_i   (device_req[DEV_GPIO]),
    .bus_addr_i  (device_addr[DEV_GPIO]),
    .bus_we_i    (device_we[DEV_GPIO]),
    .bus_wdata_i (device_wdata[DEV_GPIO]),
    .bus_rdata_o (device_rdata[DEV_GPIO]),
    .bus_rvalid_o(device_rvalid[DEV_GPIO])
  );
`else
  // GPIO未使能: 输出默认值
  assign gpio_out_o             = '0;
  assign device_rdata[DEV_GPIO] = 32'h0;
  assign device_rvalid[DEV_GPIO] = device_req[DEV_GPIO];
`endif

  // ==========================================================================
  // Timer实例化
  // ==========================================================================

  rvp_timer u_timer (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),

    // 总线接口
    .bus_req_i   (device_req[DEV_TIMER]),
    .bus_addr_i  (device_addr[DEV_TIMER]),
    .bus_we_i    (device_we[DEV_TIMER]),
    .bus_wdata_i (device_wdata[DEV_TIMER]),
    .bus_rdata_o (device_rdata[DEV_TIMER]),
    .bus_rvalid_o(device_rvalid[DEV_TIMER]),

    // 中断
    .irq_o       (timer_irq)
  );

  // ==========================================================================
  // TODO: 可选扩展功能
  // ==========================================================================

  // TODO: 添加PLIC (Platform-Level Interrupt Controller)
  // TODO: 添加CLINT (Core Local Interruptor) for mtime/mtimecmp
  // TODO: 添加调试模块 (Debug Module)
  // TODO: 添加DMA控制器
  // TODO: 添加SPI/I2C等额外外设
  // TODO: 添加WDT (Watchdog Timer)

endmodule
