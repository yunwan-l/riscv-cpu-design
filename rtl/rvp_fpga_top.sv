// =============================================================================
// rvp_fpga_top.sv — RVP FPGA 顶层封装（Nexys4 DDR）
// =============================================================================
// 功能：
//   1. 端口名匹配 Nexys4 DDR 的 XDC 约束文件
//   2. 内部例化 rvp_soc（片上系统）
//   3. 添加七段数码管动态扫描模块，显示 PC 值低 32 位（8 位十六进制）
//
// Nexys4 DDR 引脚分配（与 rvp_nexys4.xdc 一致）：
//   clk        : E3   (100 MHz 晶体振荡器)
//   rst_n      : C12  (CPU_RESETN, 低有效)
//   uart_tx    : D4   (UART_RXD_OUT, FPGA 发送)
//   led[15:0]  : 16 个用户 LED（高有效）
//   sw[15:0]   : 16 个拨码开关
//   btn_center : N17  (中心按钮，高有效)
//   seg_ca~cg  : 七段数码管段（共阳极，active low）
//   an[7:0]    : 七段数码管位选（active low）
// =============================================================================

module rvp_fpga_top (
    input  logic        clk,          // E3, 100 MHz
    input  logic        rst_n,        // C12, CPU_RESETN (低有效)
    output logic        uart_tx,      // D4, UART 发送
    output logic [15:0] led,          // 16 个 LED
    input  logic [15:0] sw,           // 16 个拨码开关
    input  logic        btn_center,   // N17, 中心按钮
    output logic        seg_ca,       // T10, 段 A (顶)
    output logic        seg_cb,       // R10, 段 B (右上)
    output logic        seg_cc,       // K16, 段 C (右下)
    output logic        seg_cd,       // K13, 段 D (底)
    output logic        seg_ce,       // P15, 段 E (左下)
    output logic        seg_cf,       // T11, 段 F (左上)
    output logic        seg_cg,       // L18, 段 G (中)
    output logic [7:0]  an            // J17~U13, 8 位位选
);

  // ===========================================================================
  // 时钟分频：100MHz → 50MHz
  // 5级流水线组合逻辑路径较长，100MHz 时序违例
  // 用 T 触发器二分频，生成 50MHz 时钟给 SoC
  // ===========================================================================
  logic clk_div2;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      clk_div2 <= 1'b0;
    else
      clk_div2 <= ~clk_div2;
  end

  // ===========================================================================
  // SoC 实例化
  // ===========================================================================
  logic [31:0] pc_dbg;

  // btn_center 目前未使用
  wire _unused_btn = btn_center;

  rvp_soc soc (
    .clk_i     (clk_div2),
    .rst_ni    (rst_n),
    .uart_tx_o (uart_tx),
    .led_o     (led),
    .sw_i      (sw),
    .pc_dbg_o  (pc_dbg)
  );

  // ===========================================================================
  // 七段数码管动态扫描
  // ===========================================================================
  // 显示 PC 值低 32 位，8 个十六进制数字
  // 刷新频率：100 MHz / 100,000 = 1 kHz（每位显示约 125 Hz）
  // 利用视觉暂留实现稳定显示

  // 分频计数器：100 MHz → 1 kHz
  logic [16:0] refresh_cnt;  // 2^17 = 131072 > 100000
  logic        refresh_en;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      refresh_cnt <= 17'd0;
    end else begin
      if (refresh_cnt == 17'd99_999) begin
        refresh_cnt <= 17'd0;
        // refresh_en 在下一个周期生效
      end else begin
        refresh_cnt <= refresh_cnt + 17'd1;
      end
    end
  end

  assign refresh_en = (refresh_cnt == 17'd99_999);

  // 位选计数器：0~7 循环
  logic [2:0] digit_sel;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      digit_sel <= 3'd0;
    end else if (refresh_en) begin
      digit_sel <= digit_sel + 3'd1;
    end
  end

  // 从 PC 值中选取当前显示的 4 位（1 个十六进制数字）
  logic [3:0] hex_digit;

  always_comb begin
    unique case (digit_sel)
      3'd0: hex_digit = pc_dbg[3:0];    // 最低位
      3'd1: hex_digit = pc_dbg[7:4];
      3'd2: hex_digit = pc_dbg[11:8];
      3'd3: hex_digit = pc_dbg[15:12];
      3'd4: hex_digit = pc_dbg[19:16];
      3'd5: hex_digit = pc_dbg[23:20];
      3'd6: hex_digit = pc_dbg[27:24];
      3'd7: hex_digit = pc_dbg[31:28];  // 最高位
    endcase
  end

  // 十六进制段码查找表
  // 编码：{CG,CF,CE,CD,CC,CB,CA}，active low（0=亮）
  logic [6:0] seg;

  always_comb begin
    unique case (hex_digit)
      4'h0: seg = 7'b1000000;  // 0:  亮 A,B,C,D,E,F
      4'h1: seg = 7'b1111001;  // 1:  亮 B,C
      4'h2: seg = 7'b0100100;  // 2:  亮 A,B,D,E,G
      4'h3: seg = 7'b0110000;  // 3:  亮 A,B,C,D,G
      4'h4: seg = 7'b0011001;  // 4:  亮 B,C,F,G
      4'h5: seg = 7'b0010010;  // 5:  亮 A,C,D,F,G
      4'h6: seg = 7'b0000010;  // 6:  亮 A,C,D,E,F,G
      4'h7: seg = 7'b1111000;  // 7:  亮 A,B,C
      4'h8: seg = 7'b0000000;  // 8:  全亮
      4'h9: seg = 7'b0010000;  // 9:  亮 A,B,C,D,F,G
      4'hA: seg = 7'b0001000;  // A:  亮 A,B,C,E,F,G
      4'hB: seg = 7'b0000011;  // b:  亮 C,D,E,F,G
      4'hC: seg = 7'b1000110;  // C:  亮 A,D,E,F
      4'hD: seg = 7'b0100001;  // d:  亮 B,C,D,E,G
      4'hE: seg = 7'b0000110;  // E:  亮 A,D,E,F,G
      4'hF: seg = 7'b0001110;  // F:  亮 A,E,F,G
    endcase
  end

  // 段信号输出（active low）
  assign seg_ca = seg[0];
  assign seg_cb = seg[1];
  assign seg_cc = seg[2];
  assign seg_cd = seg[3];
  assign seg_ce = seg[4];
  assign seg_cf = seg[5];
  assign seg_cg = seg[6];

  // 位选信号输出（active low，当前位为 0，其他为 1）
  always_comb begin
    an = 8'b11111111;  // 默认全部不选
    an[digit_sel] = 1'b0;  // 选中当前位
  end

endmodule : rvp_fpga_top
