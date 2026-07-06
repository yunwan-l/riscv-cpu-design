/**
 * rvp_ram_1p.sv - Single-Port RAM Wrapper
 *
 * RVP处理器的单端口RAM封装模块，提供32位字宽的存储器接口。
 * 支持1周期读延迟和字节级写掩码。用于仿真和FPGA综合。
 *
 * 参考: ibex shared/rtl/ram_1p.sv (71行)
 *
 * 特性:
 *   - 32位字宽存储，支持字节掩码(be_i[3:0])
 *   - 1周期读延迟 (同步读，rvalid_o在req_i后1周期拉高)
 *   - 地址转换: 字节地址 → 字索引 (addr_i[Aw-1+2:2])
 *   - 支持通过MemInitFile参数预加载固件($readmemh)
 *   - 使用SystemVerilog logic数组实现，兼容仿真和FPGA BRAM推断
 *
 * 时序说明:
 *   - 周期N: req_i=1, addr_i=A → 启动读/写
 *   - 周期N+1: rvalid_o=1, rdata_o=mem[A] (读数据有效)
 *
 * 地址格式:
 *   - addr_i为字节地址 (32位)
 *   - 低2位[1:0]为字节偏移(本模块忽略，由上层处理)
 *   - 中间Aw位[Aw-1+2:2]为字索引
 *   - 高位[31:Aw+2]为未使用地址部分
 */

`include "rvp_config.svh"

module rvp_ram_1p #(
    /// 存储深度(字数)。默认128个32位字 = 512字节
    parameter int         Depth       = 128,
    /// 预加载文件路径(HEX格式，用于$readmemh)。空字符串=不加载
    parameter             MemInitFile = ""
) (
    input  logic         clk_i,        // 时钟
    input  logic         rst_ni,       // 异步低有效复位

    input  logic         req_i,        // 请求有效(读或写)
    input  logic         we_i,         // 写使能 (1=写, 0=读)
    input  logic [ 3:0]  be_i,         // 字节使能掩码 (be_i[0]=字节0, ..., be_i[3]=字节3)
    input  logic [31:0]  addr_i,       // 字节地址
    input  logic [31:0]  wdata_i,      // 写数据

    output logic         rvalid_o,     // 读数据有效 (延迟1周期)
    output logic [31:0]  rdata_o       // 读数据
);

  // ==========================================================================
  // 本地参数计算
  // ==========================================================================

  // 地址位宽: 字索引所需的位数 (log2(Depth))
  localparam int Aw = $clog2(Depth);

  // ==========================================================================
  // 地址转换: 字节地址 → 字索引
  // ==========================================================================

  // 从字节地址中提取字索引
  // addr_i[Aw-1+2:2] 选中存储器中的字
  logic [Aw-1:0] addr_idx;
  assign addr_idx = addr_i[Aw-1+2:2];

  // 未使用的地址部分 (高位和低2位字节偏移)
  logic [31-Aw:0] unused_addr_parts;
  assign unused_addr_parts = {addr_i[31:Aw+2], addr_i[1:0]};

  // ==========================================================================
  // 字节掩码转换: be_i[3:0] → 32位位掩码
  // ==========================================================================

  // 将4位字节使能转换为32位位掩码，每位对应一个数据位
  // be_i[i]=1 → wmask[8*i +: 8] = 8'hFF (该字节允许写入)
  logic [31:0] wmask;
  always_comb begin
    for (int i = 0; i < 4; i++) begin
      wmask[8*i +: 8] = {8{be_i[i]}};
    end
  end

  // ==========================================================================
  // 存储器阵列
  // ==========================================================================

  // 使用logic数组定义存储器阵列
  // 综合工具通常能将其推断为Block RAM或分布式RAM
  logic [31:0] mem [Depth];

  // 预加载固件 (仿真用)
  initial begin
    if (MemInitFile != "") begin
      $readmemh(MemInitFile, mem);
    end
  end

  // ==========================================================================
  // 读/写逻辑
  // ==========================================================================

  // 同步写操作 (带字节掩码)
  // 仅写入be_i使能的字节，其余字节保持不变
  always_ff @(posedge clk_i) begin
    if (req_i && we_i) begin
      for (int i = 0; i < 4; i++) begin
        if (be_i[i]) begin
          mem[addr_idx][8*i +: 8] <= wdata_i[8*i +: 8];
        end
      end
    end
  end

  // 同步读操作 (1周期延迟)
  // 读数据在req_i后的下一个周期有效
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_o <= 32'h0;
    end else if (req_i) begin
      rdata_o <= mem[addr_idx];
    end
  end

  // ==========================================================================
  // 读有效信号 (rvalid_o = req_i 延迟1周期)
  // ==========================================================================

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid_o <= 1'b0;
    end else begin
      rvalid_o <= req_i;
    end
  end

  // ==========================================================================
  // 综合属性 (可选 - 帮助FPGA工具推断BRAM)
  // ==========================================================================

  // Vivado BRAM推断属性
  // (* ram_style = "block" *)

  // TODO: 根据目标平台添加综合属性
  //   - Vivado: (* ram_style = "block" *) 或 "distributed"
  //   - Quartus: (* ramstyle = "M9K" *) 或 "no_rw_check"
  // TODO: 添加ECC(纠错码)支持 (可选)
  // TODO: 添加寄存器初始化值属性 (用于FPGA上电初始化)

endmodule
