// =============================================================================
// rvp_gpio.sv — RVP 通用输入输出外设
// =============================================================================
// 功能：控制 FPGA 板上的 LED 灯，读取拨码开关/按键
//
// 寄存器映射：
//   偏移 0x00: OUTPUT (R/W) — 写入的值直接驱动 LED 引脚
//   偏移 0x04: INPUT  (R)   — 读取外部输入（开关/按键）的当前值
//
// 接口：
//   clk_i, rst_ni : 时钟和复位
//   addr_i[3:0]   : 寄存器偏移
//   read_i        : 读使能
//   write_i       : 写使能
//   wdata_i       : 写数据
//   rdata_o       : 读返回数据
//   led_o         : LED 输出引脚（宽度可参数化）
//   sw_i          : 开关输入引脚
// =============================================================================

module rvp_gpio #(
  parameter int WIDTH = 16  // 引脚宽度（NEXYS4 有 16 个 LED 和 16 个开关）
) (
  input  logic             clk_i,
  input  logic             rst_ni,

  // 总线接口
  input  logic [31:0]      addr_i,
  input  logic             read_i,
  input  logic             write_i,
  input  logic [31:0]      wdata_i,
  output logic [31:0]      rdata_o,

  // 物理引脚
  output logic [WIDTH-1:0] led_o,
  input  logic [WIDTH-1:0] sw_i
);

  logic [WIDTH-1:0] output_reg;

  // 写 OUTPUT 寄存器
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      output_reg <= '0;
    end else if (write_i && addr_i[3:0] == 4'h0) begin
      output_reg <= wdata_i[WIDTH-1:0];
    end
  end

  // LED 输出
  assign led_o = output_reg;

  // 读寄存器
  always_comb begin
    rdata_o = 32'b0;
    if (read_i) begin
      unique case (addr_i[3:0])
        4'h0:    rdata_o = {{(32-WIDTH){1'b0}}, output_reg};  // OUTPUT
        4'h4:    rdata_o = {{(32-WIDTH){1'b0}}, sw_i};        // INPUT
        default: rdata_o = 32'b0;
      endcase
    end
  end

endmodule : rvp_gpio
