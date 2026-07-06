/**
 * rvp_data_mem.sv - Data Memory Wrapper
 *
 * RVP处理器的数据存储器封装模块，内部实例化rvp_ram_1p。
 * 提供完整的数据访存接口，支持读/写操作和字节掩码。
 *
 * 功能:
 *   - 封装rvp_ram_1p为可读写数据存储器
 *   - 支持通过MemInitFile参数预加载初始数据
 *   - 32位字宽，1周期读延迟
 *   - 支持字节级写掩码 (be_i[3:0])
 *
 * 使用场景:
 *   - SoC中映射到0x0001_0000地址空间的数据存储器
 *   - 用于存放全局变量、栈、堆等数据
 *
 * 地址说明:
 *   - addr_i为字节地址 (来自CPU数据总线)
 *   - 内部由rvp_ram_1p自动转换为字索引
 */

`include "rvp_config.svh"

module rvp_data_mem #(
    /// 存储深度(字数)。默认32KB/4 = 8192字
    /// 从RVP_DATA_MEM_SIZE宏获取 (默认32768字节)
    parameter int         Depth       = `RVP_DATA_MEM_SIZE / 4,
    /// 预加载初始数据文件路径 (HEX格式)
    parameter             MemInitFile = ""
) (
    input  logic         clk_i,        // 时钟
    input  logic         rst_ni,       // 异步低有效复位

    input  logic         req_i,        // 访存请求
    input  logic         we_i,         // 写使能 (1=写, 0=读)
    input  logic [ 3:0]  be_i,         // 字节使能掩码
    input  logic [31:0]  addr_i,       // 数据字节地址
    input  logic [31:0]  wdata_i,      // 写数据
    output logic [31:0]  rdata_o,      // 读数据
    output logic         rvalid_o      // 读有效 (1周期延迟)
);

  // ==========================================================================
  // 单端口RAM实例化
  // ==========================================================================

  rvp_ram_1p #(
    .Depth       (Depth),
    .MemInitFile (MemInitFile)
  ) u_ram_1p (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),

    .req_i     (req_i),
    .we_i      (we_i),
    .be_i      (be_i),
    .addr_i    (addr_i),
    .wdata_i   (wdata_i),

    .rvalid_o  (rvalid_o),
    .rdata_o   (rdata_o)
  );

  // ==========================================================================
  // TODO: 可选扩展功能
  // ==========================================================================

  // TODO: 添加数据存储器访问计数 (性能分析用)
  // TODO: 添加总线错误检测 (地址越界检查)
  // TODO: 添加ECC校验逻辑 (可选)
  // TODO: 添加存储器保护 (PMP检查)

endmodule
