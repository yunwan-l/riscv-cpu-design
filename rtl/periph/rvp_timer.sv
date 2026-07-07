// =============================================================================
// rvp_timer.sv — RVP 定时器外设
// =============================================================================
// 功能：32 位自由运行计数器，可用于延时和简单计时
//
// 寄存器映射：
//   偏移 0x00: COUNT (R)   — 当前计数值（每时钟周期 +1，当 enable=1 时）
//   偏移 0x04: CTRL   (R/W) — bit[0]: enable (1=计数, 0=暂停)
//                             bit[1]: clear  (写 1 清零计数器，自动清零)
//
// 典型用法：
//   1. 写 CTRL=0x1 启动计数
//   2. 读 COUNT 获取当前值
//   3. 两次读 COUNT 的差值 / 时钟频率 = 经过的时间（秒）
//   4. 写 CTRL=0x2 清零后重新开始
//
// 接口：
//   clk_i, rst_ni : 时钟和复位
//   addr_i[3:0]   : 寄存器偏移
//   read_i        : 读使能
//   write_i       : 写使能
//   wdata_i       : 写数据
//   rdata_o       : 读返回数据
// =============================================================================

module rvp_timer (
  input  logic        clk_i,
  input  logic        rst_ni,

  // 总线接口
  input  logic [31:0] addr_i,
  input  logic        read_i,
  input  logic        write_i,
  input  logic [31:0] wdata_i,
  output logic [31:0] rdata_o
);

  logic [31:0] count;
  logic        enable;

  // 寄存器写入
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count  <= 32'b0;
      enable <= 1'b0;
    end else begin
      // 写 CTRL
      if (write_i && addr_i[3:0] == 4'h4) begin
        enable <= wdata_i[0];
        if (wdata_i[1]) begin
          count <= 32'b0;  // clear
        end
      end else if (enable) begin
        count <= count + 32'd1;
      end
    end
  end

  // 寄存器读取
  always_comb begin
    rdata_o = 32'b0;
    if (read_i) begin
      unique case (addr_i[3:0])
        4'h0:    rdata_o = count;                      // COUNT
        4'h4:    rdata_o = {30'b0, enable, 1'b0};      // CTRL (clear 位读回 0)
        default: rdata_o = 32'b0;
      endcase
    end
  end

endmodule : rvp_timer
