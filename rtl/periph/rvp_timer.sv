/**
 * rvp_timer.sv - Programmable Timer Module
 *
 * RVP处理器的可编程定时器模块，提供32位递减计数器和溢出中断。
 * 支持预分频配置和比较匹配中断。
 *
 * 参考: ibex shared/rtl/timer.sv
 *
 * 功能:
 *   - 32位递减计数器 (从加载值递减到0)
 *   - 可配置预分频器 (1周期~65536周期)
 *   - 计数到0时自动重装并产生中断
 *   - 内存映射寄存器接口
 *   - 溢出中断输出
 *
 * 寄存器映射 (偏移地址):
 *   0x00: TIMER_LOAD   (读写) - 计数器加载值 (递减起始值)
 *   0x04: TIMER_COUNT   (只读) - 当前计数值
 *   0x08: TIMER_CTRL    (读写) - 控制寄存器
 *   0x0C: TIMER_PRESC   (读写) - 预分频值
 *
 * 控制寄存器 (TIMER_CTRL) 位定义:
 *   [0] = 定时器使能 (1=运行, 0=停止)
 *   [1] = 模式 (0=单次, 1=自动重装)
 *   [2] = 中断使能
 *   [3] = 中断标志 (写1清除)
 *
 * 使用场景:
 *   - SoC中映射到0x1002_0000地址空间
 *   - 为RISC-V mtimer CSR提供时钟源
 *   - 产生周期性中断
 */

`include "rvp_config.svh"

module rvp_timer (
    input  logic         clk_i,          // 时钟
    input  logic         rst_ni,         // 异步低有效复位

    // ==========================================================================
    // 总线接口 (内存映射)
    // ==========================================================================
    input  logic         bus_req_i,       // 总线请求
    input  logic [31:0]  bus_addr_i,      // 总线地址
    input  logic         bus_we_i,         // 总线写使能
    input  logic [31:0]  bus_wdata_i,     // 总线写数据
    output logic [31:0]  bus_rdata_o,     // 总线读数据
    output logic         bus_rvalid_o,    // 总线读有效

    // ==========================================================================
    // 中断输出
    // ==========================================================================
    output logic         irq_o            // 溢出中断输出
);

  // ==========================================================================
  // 寄存器偏移地址定义
  // ==========================================================================

  localparam logic [3:0] REG_TIMER_LOAD  = 4'h0;  // 0x00: 加载值
  localparam logic [3:0] REG_TIMER_COUNT = 4'h4;  // 0x04: 当前计数值
  localparam logic [3:0] REG_TIMER_CTRL  = 4'h8;  // 0x08: 控制寄存器
  localparam logic [3:0] REG_TIMER_PRESC = 4'hC;  // 0x0C: 预分频值

  // ==========================================================================
  // 控制寄存器位定义
  // ==========================================================================

  localparam int CTRL_ENABLE    = 0;  // [0] 使能
  localparam int CTRL_MODE      = 1;  // [1] 模式 (0=单次, 1=自动重装)
  localparam int CTRL_IRQ_EN   = 2;  // [2] 中断使能
  localparam int CTRL_IRQ_FLAG = 3;  // [3] 中断标志 (写1清除)

  // ==========================================================================
  // 寄存器存储
  // ==========================================================================

  logic [31:0] load_val_q;      // 加载值寄存器
  logic [31:0] count_q;         // 当前计数值
  logic [31:0] ctrl_q;          // 控制寄存器
  logic [15:0] presc_q;         // 预分频值
  logic [15:0] presc_count_q;   // 预分频计数器

  // 控制寄存器各位别名
  logic        timer_enable;     // 使能
  logic        timer_mode;       // 模式 (0=单次, 1=自动重装)
  logic        timer_irq_en;     // 中断使能
  logic        timer_irq_flag;   // 中断标志

  assign timer_enable   = ctrl_q[CTRL_ENABLE];
  assign timer_mode     = ctrl_q[CTRL_MODE];
  assign timer_irq_en   = ctrl_q[CTRL_IRQ_EN];
  assign timer_irq_flag = ctrl_q[CTRL_IRQ_FLAG];

  // 预分频到达信号 (当预分频计数器归零时为1)
  logic        presc_tick;

  // ==========================================================================
  // 预分频逻辑
  // ==========================================================================

  // 预分频计数器: 每presc_q+1个时钟周期产生一次tick
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      presc_count_q <= 16'h0;
    end else if (!timer_enable) begin
      presc_count_q <= 16'h0;
    end else if (presc_count_q >= presc_q) begin
      presc_count_q <= 16'h0;
    end else begin
      presc_count_q <= presc_count_q + 16'd1;
    end
  end

  // 预分频tick: 计数器归零时产生
  assign presc_tick = timer_enable && (presc_count_q >= presc_q);

  // ==========================================================================
  // 递减计数器逻辑
  // ==========================================================================

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      count_q <= 32'h0;
    end else if (!timer_enable) begin
      // 定时器停止时，加载值
      count_q <= load_val_q;
    end else if (presc_tick) begin
      // 预分频到达时递减
      if (count_q == 32'h0) begin
        // 计数器到达0
        if (timer_mode) begin
          // 自动重装模式: 重新加载
          count_q <= load_val_q;
        end else begin
          // 单次模式: 停止计数
          count_q <= 32'h0;
        end
      end else begin
        // 递减
        count_q <= count_q - 32'd1;
      end
    end
  end

  // ==========================================================================
  // 中断标志逻辑
  // ==========================================================================

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      ctrl_q[CTRL_IRQ_FLAG] <= 1'b0;
    end else if (bus_req_i && bus_we_i &&
                bus_addr_i[3:0] == REG_TIMER_CTRL &&
                bus_wdata_i[CTRL_IRQ_FLAG]) begin
      // 写1清除中断标志
      ctrl_q[CTRL_IRQ_FLAG] <= 1'b0;
    end else if (timer_enable && presc_tick && (count_q == 32'h0)) begin
      // 计数器溢出: 置位中断标志
      ctrl_q[CTRL_IRQ_FLAG] <= 1'b1;
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
      load_val_q <= 32'h0000_FFFF;  // 默认加载值
      ctrl_q     <= 32'h0;          // 默认停止, 单次, 中断禁用
      presc_q    <= 16'h0000;        // 默认无预分频 (每周期递减)
    end else if (bus_req_i && bus_we_i) begin
      unique case (reg_addr)
        REG_TIMER_LOAD: begin
          load_val_q <= bus_wdata_i;
        end
        REG_TIMER_CTRL: begin
          // 写控制寄存器 (但不覆盖中断标志位，中断标志由单独逻辑处理)
          ctrl_q[CTRL_ENABLE]  <= bus_wdata_i[CTRL_ENABLE];
          ctrl_q[CTRL_MODE]    <= bus_wdata_i[CTRL_MODE];
          ctrl_q[CTRL_IRQ_EN]  <= bus_wdata_i[CTRL_IRQ_EN];
          // 注意: CTRL_IRQ_FLAG由上面的单独逻辑处理
        end
        REG_TIMER_PRESC: begin
          presc_q <= bus_wdata_i[15:0];
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
      REG_TIMER_LOAD: begin
        rdata_q = load_val_q;
      end
      REG_TIMER_COUNT: begin
        rdata_q = count_q;
      end
      REG_TIMER_CTRL: begin
        rdata_q = ctrl_q;
      end
      REG_TIMER_PRESC: begin
        rdata_q = {16'h0, presc_q};
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
  // 中断输出
  // ==========================================================================

  // 中断条件: 中断使能且中断标志置位
  assign irq_o = timer_irq_en && timer_irq_flag;

  // ==========================================================================
  // TODO: 可选扩展功能
  // ==========================================================================

  // TODO: 添加64位mtimer支持 (兼容RISC-V CLINT)
  // TODO: 添加比较匹配寄存器 (mtimecmp)
  // TODO: 添加多种中断模式 (上升沿/电平/自动清除)
  // TODO: 添加计数器方向配置 (递增/递减)

endmodule
