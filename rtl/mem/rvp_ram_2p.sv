/**
 * rvp_ram_2p.sv - Dual-Port RAM Wrapper
 *
 * RVP处理器的双端口RAM封装模块，提供两个独立访问端口的32位存储器接口。
 * 支持指令和数据分离访问 (哈佛架构)，B端口可配置额外延迟以模拟慢速存储器。
 *
 * 参考: ibex shared/rtl/ram_2p.sv (114行)
 *
 * 特性:
 *   - 双端口独立访问 (A端口和B端口可同时读/写)
 *   - 32位字宽存储，支持字节掩码
 *   - 1周期读延迟 (同步读)
 *   - B端口支持可配置额外延迟 (BExtraDelay参数)
 *   - 支持通过MemInitFile参数预加载固件
 *
 * 端口分配建议:
 *   - A端口: 数据访问 (由CPU数据总线连接)
 *   - B端口: 指令取指 (由CPU指令总线连接)
 *
 * BExtraDelay说明:
 *   - BExtraDelay=0: B端口1周期延迟 (与A端口相同)
 *   - BExtraDelay=N: B端口额外增加N周期延迟 (模拟慢速Flash等)
 *
 * 地址格式 (与rvp_ram_1p相同):
 *   - addr为字节地址
 *   - 低2位[1:0]为字节偏移
 *   - 中间Aw位[Aw-1+2:2]为字索引
 */

`include "rvp_config.svh"

module rvp_ram_2p #(
    /// 存储深度(字数)
    parameter int         Depth       = 128,
    /// B端口额外延迟周期数 (0=无额外延迟，N=额外N周期延迟)
    parameter int         BExtraDelay = 0,
    /// 预加载文件路径(HEX格式)
    parameter             MemInitFile = ""
) (
    input  logic         clk_i,        // 时钟
    input  logic         rst_ni,       // 异步低有效复位

    // ==========================================================================
    // A端口 (通常用于数据访问)
    // ==========================================================================
    input  logic         a_req_i,      // A端口请求
    input  logic         a_we_i,       // A端口写使能
    input  logic [ 3:0]  a_be_i,       // A端口字节使能
    input  logic [31:0]  a_addr_i,     // A端口字节地址
    input  logic [31:0]  a_wdata_i,    // A端口写数据
    output logic         a_rvalid_o,   // A端口读有效
    output logic [31:0]  a_rdata_o,    // A端口读数据

    // ==========================================================================
    // B端口 (通常用于指令取指)
    // ==========================================================================
    input  logic         b_req_i,      // B端口请求
    input  logic         b_we_i,       // B端口写使能
    input  logic [ 3:0]  b_be_i,       // B端口字节使能
    input  logic [31:0]  b_addr_i,     // B端口字节地址
    input  logic [31:0]  b_wdata_i,    // B端口写数据
    output logic         b_rvalid_o,   // B端口读有效
    output logic [31:0]  b_rdata_o     // B端口读数据
);

  // ==========================================================================
  // 本地参数计算
  // ==========================================================================

  localparam int Aw = $clog2(Depth);

  // ==========================================================================
  // A端口地址转换: 字节地址 → 字索引
  // ==========================================================================

  logic [Aw-1:0] a_addr_idx;
  assign a_addr_idx = a_addr_i[Aw-1+2:2];

  logic [31-Aw:0] unused_a_addr_parts;
  assign unused_a_addr_parts = {a_addr_i[31:Aw+2], a_addr_i[1:0]};

  // ==========================================================================
  // B端口地址转换: 字节地址 → 字索引
  // ==========================================================================

  logic [Aw-1:0] b_addr_idx;
  assign b_addr_idx = b_addr_i[Aw-1+2:2];

  logic [31-Aw:0] unused_b_addr_parts;
  assign unused_b_addr_parts = {b_addr_i[31:Aw+2], b_addr_i[1:0]};

  // ==========================================================================
  // 字节掩码转换: be_i[3:0] → 32位位掩码
  // ==========================================================================

  logic [31:0] a_wmask;
  logic [31:0] b_wmask;
  always_comb begin
    for (int i = 0; i < 4; i++) begin
      a_wmask[8*i +: 8] = {8{a_be_i[i]}};
      b_wmask[8*i +: 8] = {8{b_be_i[i]}};
    end
  end

  // ==========================================================================
  // 存储器阵列 (双端口共享)
  // ==========================================================================

  logic [31:0] mem [Depth];

  // 预加载固件
  initial begin
    if (MemInitFile != "") begin
      $readmemh(MemInitFile, mem);
    end
  end

  // ==========================================================================
  // A端口读/写逻辑
  // ==========================================================================

  // A端口同步写 (带字节掩码)
  always_ff @(posedge clk_i) begin
    if (a_req_i && a_we_i) begin
      for (int i = 0; i < 4; i++) begin
        if (a_be_i[i]) begin
          mem[a_addr_idx][8*i +: 8] <= a_wdata_i[8*i +: 8];
        end
      end
    end
  end

  // A端口同步读 (1周期延迟)
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      a_rdata_o <= 32'h0;
    end else if (a_req_i) begin
      a_rdata_o <= mem[a_addr_idx];
    end
  end

  // A端口读有效信号
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      a_rvalid_o <= 1'b0;
    end else begin
      a_rvalid_o <= a_req_i;
    end
  end

  // ==========================================================================
  // B端口读/写逻辑
  // ==========================================================================

  // B端口同步写 (带字节掩码)
  // 注意: A和B同时写同一地址时行为未定义 (软件应避免)
  always_ff @(posedge clk_i) begin
    if (b_req_i && b_we_i) begin
      for (int i = 0; i < 4; i++) begin
        if (b_be_i[i]) begin
          mem[b_addr_idx][8*i +: 8] <= b_wdata_i[8*i +: 8];
        end
      end
    end
  end

  // B端口同步读 (1周期基础延迟 + BExtraDelay额外延迟)
  // 当BExtraDelay=0时，与A端口相同
  // 当BExtraDelay>0时，额外插入N级流水寄存器
  logic [31:0] b_rdata_d;       // B端口直接读数据 (1周期)
  logic        b_rvalid_d;      // B端口直接读有效 (1周期)

  // 延迟流水线寄存器 (仅当BExtraDelay > 0时使用)
  logic        b_rvalid_q [(BExtraDelay == 0) ? 1 : BExtraDelay];
  logic [31:0] b_rdata_q  [(BExtraDelay == 0) ? 1 : BExtraDelay];

  // B端口基础读 (1周期)
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      b_rdata_d <= 32'h0;
    end else if (b_req_i) begin
      b_rdata_d <= mem[b_addr_idx];
    end
  end

  // B端口基础读有效
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      b_rvalid_d <= 1'b0;
    end else begin
      b_rvalid_d <= b_req_i;
    end
  end

  // ==========================================================================
  // B端口额外延迟流水线
  // ==========================================================================

  // 当BExtraDelay=0时，直接输出1周期延迟结果
  // 当BExtraDelay>0时，通过流水寄存器增加N周期延迟
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < BExtraDelay; i++) begin
        b_rvalid_q[i] <= 1'b0;
        b_rdata_q[i]  <= 32'h0;
      end
    end else begin
      // 流水寄存器链
      b_rvalid_q[0] <= b_rvalid_d;
      b_rdata_q[0]  <= b_rdata_d;
      for (int i = BExtraDelay - 1; i > 0; i--) begin
        b_rvalid_q[i] <= b_rvalid_q[i-1];
        b_rdata_q[i]  <= b_rdata_q[i-1];
      end
    end
  end

  // B端口输出选择
  assign b_rvalid_o = (BExtraDelay == 0) ? b_rvalid_d : b_rvalid_q[BExtraDelay-1];
  assign b_rdata_o  = (BExtraDelay == 0) ? b_rdata_d  : b_rdata_q[BExtraDelay-1];

  // ==========================================================================
  // 综合属性 (可选)
  // ==========================================================================

  // TODO: 根据目标平台添加双端口RAM综合属性
  // TODO: 添加读写冲突检测 (同一周期A写B读同一地址时的转发逻辑)

endmodule
