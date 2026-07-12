// =============================================================================
// rvp_gpio.sv — RVP 通用输入输出外设
// =============================================================================
// 功能：控制 FPGA 板上的 LED 灯，读取拨码开关/按键
//
// 寄存器映射：
//   偏移 0x00: OUTPUT (R/W) — 写入的值直接驱动 LED 引脚
//   偏移 0x04: INPUT  (R)   — 读取外部输入（开关/按键）的当前值
//   偏移 0x08: SNAP_HIT   (W) — 快照：I-Cache hit_delta（固件写入，数码管读取）
//   偏移 0x0C: SNAP_MISS  (W) — 快照：I-Cache miss_delta
//   偏移 0x10: SNAP_TOTAL (W) — 快照：total_delta
//
// 接口：
//   clk_i, rst_ni    : 时钟和复位
//   addr_i[4:0]      : 寄存器偏移
//   read_i           : 读使能
//   write_i          : 写使能
//   wdata_i[WIDTH-1:0]: 写数据（宽度与引脚一致）
//   rdata_o          : 读返回数据
//   led_o            : LED 输出引脚（宽度可参数化）
//   sw_i             : 开关输入引脚
// =============================================================================

module rvp_gpio #(
  parameter int WIDTH = 16  // 引脚宽度（NEXYS4 有 16 个 LED 和 16 个开关）
) (
  input  logic             clk_i,
  input  logic             rst_ni,

  // 总线接口（端口宽度与实际使用一致，避免综合 unconnected port warning）
  input  logic [4:0]       addr_i,
  input  logic             read_i,
  input  logic             write_i,
  input  logic [31:0]      wdata_i,
  output logic [31:0]      rdata_o,

  // 物理引脚
  output logic [WIDTH-1:0] led_o,
  input  logic [WIDTH-1:0] sw_i,

  // 快照寄存器输出（数码管显示用）
  output logic [31:0]      snap_hit_o,
  output logic [31:0]      snap_miss_o,
  output logic [31:0]      snap_total_o
);

  logic [WIDTH-1:0] output_reg;
  logic [31:0]      snap_hit_reg;
  logic [31:0]      snap_miss_reg;
  logic [31:0]      snap_total_reg;

  // 写 OUTPUT 和快照寄存器
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      output_reg    <= '0;
      snap_hit_reg   <= '0;
      snap_miss_reg  <= '0;
      snap_total_reg <= '0;
    end else if (write_i) begin
      case (addr_i)
        5'h00:   output_reg    <= wdata_i[WIDTH-1:0];  // LED只取低16位
        5'h08:   snap_hit_reg   <= wdata_i;             // 32位快照
        5'h0C:   snap_miss_reg  <= wdata_i;
        5'h10:   snap_total_reg <= wdata_i;
        default: ;
      endcase
    end
  end

  // LED 输出
  assign led_o        = output_reg;
  assign snap_hit_o   = snap_hit_reg;
  assign snap_miss_o  = snap_miss_reg;
  assign snap_total_o = snap_total_reg;

  // 读寄存器
  always_comb begin
    rdata_o = 32'b0;
    if (read_i) begin
      unique case (addr_i)
        5'h00:   rdata_o = {{(32-WIDTH){1'b0}}, output_reg};  // OUTPUT
        5'h04:   rdata_o = {{(32-WIDTH){1'b0}}, sw_i};        // INPUT
        default: rdata_o = 32'b0;
      endcase
    end
  end

endmodule : rvp_gpio
