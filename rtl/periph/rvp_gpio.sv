/**
 * rvp_gpio.sv - General Purpose I/O Controller
 *
 * RVP处理器的GPIO控制器模块，提供可编程的通用输入输出引脚控制。
 * 支持方向配置、输入读取、输出写入和中断使能。
 *
 * 功能:
 *   - 可配置GPIO宽度 (GPIO_WIDTH参数)
 *   - 每个引脚方向可独立配置 (输入/输出)
 *   - 输入引脚实时采样
 *   - 输出引脚寄存器驱动
 *   - 电平中断支持 (可配置中断使能掩码)
 *
 * 寄存器映射 (偏移地址):
 *   0x00: GPIO_IN   (只读) - 输入引脚当前值
 *   0x04: GPIO_OUT  (读写) - 输出引脚寄存器值
 *   0x08: GPIO_DIR  (读写) - 方向控制 (0=输入, 1=输出)
 *   0x0C: GPIO_IE   (读写) - 中断使能掩码
 *
 * 使用场景:
 *   - SoC中映射到0x1001_0000地址空间
 *   - 驱动LED、读取按键、连接传感器等
 */

`include "rvp_config.svh"

module rvp_gpio #(
    /// GPIO引脚数量
    parameter int GPIO_WIDTH = `RVP_GPIO_WIDTH
) (
    input  logic             clk_i,          // 时钟
    input  logic             rst_ni,         // 异步低有效复位

    // ==========================================================================
    // GPIO物理接口
    // ==========================================================================
    input  logic [GPIO_WIDTH-1:0] gpio_in_i,     // GPIO输入引脚
    output logic [GPIO_WIDTH-1:0] gpio_out_o,     // GPIO输出引脚

    // ==========================================================================
    // 总线接口 (内存映射)
    // ==========================================================================
    input  logic             bus_req_i,       // 总线请求
    input  logic [31:0]      bus_addr_i,      // 总线地址
    input  logic             bus_we_i,         // 总线写使能
    input  logic [31:0]      bus_wdata_i,     // 总线写数据
    output logic [31:0]      bus_rdata_o,     // 总线读数据
    output logic             bus_rvalid_o      // 总线读有效
);

  // ==========================================================================
  // 寄存器偏移地址定义
  // ==========================================================================

  localparam logic [3:0] REG_GPIO_IN  = 4'h0;  // 0x00: 输入值 (只读)
  localparam logic [3:0] REG_GPIO_OUT = 4'h4;  // 0x04: 输出值 (读写)
  localparam logic [3:0] REG_GPIO_DIR = 4'h8;  // 0x08: 方向 (0=in, 1=out)
  localparam logic [3:0] REG_GPIO_IE  = 4'hC;  // 0x0C: 中断使能

  // ==========================================================================
  // 寄存器存储
  // ==========================================================================

  logic [GPIO_WIDTH-1:0] gpio_out_q;    // 输出寄存器
  logic [GPIO_WIDTH-1:0] gpio_dir_q;    // 方向寄存器 (0=输入, 1=输出)
  logic [GPIO_WIDTH-1:0] gpio_ie_q;      // 中断使能寄存器
  logic [GPIO_WIDTH-1:0] gpio_in_sync;   // 同步后的输入值 (2级同步)

  // ==========================================================================
  // 输入同步 (2级触发器，消除亚稳态)
  // ==========================================================================

  logic [GPIO_WIDTH-1:0] gpio_in_meta;   // 第一级 (亚稳态可能存在)

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      gpio_in_meta <= '0;
      gpio_in_sync <= '0;
    end else begin
      gpio_in_meta <= gpio_in_i;     // 第一级: 采样 (可能亚稳态)
      gpio_in_sync <= gpio_in_meta;  // 第二级: 稳定
    end
  end

  // ==========================================================================
  // 寄存器写逻辑
  // ==========================================================================

  // 地址解码 (取低4位)
  logic [3:0] reg_addr;
  assign reg_addr = bus_addr_i[3:0];

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      gpio_out_q <= '0;
      gpio_dir_q <= '0;  // 默认全部为输入
      gpio_ie_q  <= '0;  // 默认无中断
    end else if (bus_req_i && bus_we_i) begin
      unique case (reg_addr)
        REG_GPIO_OUT: begin
          gpio_out_q <= bus_wdata_i[GPIO_WIDTH-1:0];
        end
        REG_GPIO_DIR: begin
          gpio_dir_q <= bus_wdata_i[GPIO_WIDTH-1:0];
        end
        REG_GPIO_IE: begin
          gpio_ie_q <= bus_wdata_i[GPIO_WIDTH-1:0];
        end
        default: ; // 无操作 (GPIO_IN为只读)
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
      REG_GPIO_IN: begin
        rdata_q = {{(32-GPIO_WIDTH){1'b0}}, gpio_in_sync};
      end
      REG_GPIO_OUT: begin
        rdata_q = {{(32-GPIO_WIDTH){1'b0}}, gpio_out_q};
      end
      REG_GPIO_DIR: begin
        rdata_q = {{(32-GPIO_WIDTH){1'b0}}, gpio_dir_q};
      end
      REG_GPIO_IE: begin
        rdata_q = {{(32-GPIO_WIDTH){1'b0}}, gpio_ie_q};
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
  // GPIO输出驱动
  // ==========================================================================

  // 仅方向为输出的引脚驱动输出值，输入引脚输出高阻
  // 注意: 实际三态控制在FPGA顶层实现，这里仅提供输出值
  always_comb begin
    for (int i = 0; i < GPIO_WIDTH; i++) begin
      if (gpio_dir_q[i]) begin
        gpio_out_o[i] = gpio_out_q[i];  // 输出模式: 驱动输出值
      end else begin
        gpio_out_o[i] = 1'bz;           // 输入模式: 高阻
      end
    end
  end

  // ==========================================================================
  // 中断逻辑 (可选)
  // ==========================================================================

  // 中断输出信号 (未连接到顶层端口，供扩展使用)
  // TODO: 实现电平中断: 当使能的输入引脚为高时产生中断
  // TODO: 或边沿中断: 检测输入引脚变化沿
  // logic [GPIO_WIDTH-1:0] gpio_in_prev;
  // logic irq_gpio;
  // always_ff @(posedge clk_i, negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     gpio_in_prev <= '0;
  //   end else begin
  //     gpio_in_prev <= gpio_in_sync;
  //   end
  // end
  // assign irq_gpio = |(gpio_ie_q & gpio_in_sync);

  // ==========================================================================
  // TODO: 可选扩展功能
  // ==========================================================================

  // TODO: 添加中断输出端口 irq_o
  // TODO: 添加上升沿/下降沿中断检测模式
  // TODO: 添加GPIO引脚复用控制 (mux)
  // TODO: 添加输出使能寄存器 (独立于方向寄存器)

endmodule
