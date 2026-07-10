/**
 * rvp_instr_mem.sv - Instruction Memory Wrapper
 *
 * RVP处理器的指令存储器封装模块，内部实例化rvp_ram_1p。
 * 提供简化的只读取指接口，适用于指令存储器区域。
 *
 * 功能:
 *   - 封装rvp_ram_1p为只读指令存储器
 *   - 支持通过MemInitFile参数预加载固件 ($readmemh)
 *   - 32位字宽，1周期读延迟
 *   - 不支持写操作 (we_i固定为0)
 *
 * 使用场景:
 *   - SoC中映射到0x0000_0000地址空间的指令存储器
 *   - 可通过$readmemh在仿真启动时加载编译好的固件
 *
 * 地址说明:
 *   - addr_i为字节地址 (来自CPU的instr_addr_o)
 *   - 内部由rvp_ram_1p自动转换为字索引
 */

`include "rvp_config.svh"

module rvp_instr_mem #(
    /// 存储深度(字数)。默认32KB/4 = 8192字
    /// 从RVP_INSTR_MEM_SIZE宏获取 (默认32768字节)
    parameter int         Depth       = `RVP_INSTR_MEM_SIZE / 4,
    /// 预加载固件文件路径 (HEX格式)
    parameter             MemInitFile = ""
) (
    input  logic         clk_i,        // 时钟
    input  logic         rst_ni,       // 异步低有效复位

    input  logic         req_i,        // 取指请求
    input  logic [31:0]  addr_i,       // 指令字节地址
    output logic [31:0]  rdata_o,      // 读出的指令数据
    output logic         rvalid_o      // 读数据有效 (1周期延迟)
);

  // ==========================================================================
  // 内部信号
  // ==========================================================================

  // 写使能: 指令存储器只读，we固定为0
  logic        ram_we;
  logic [ 3:0] ram_be;
  logic [31:0] ram_wdata;

  assign ram_we    = 1'b0;       // 只读存储器
  assign ram_be    = 4'b0000;     // 无写掩码
  assign ram_wdata = 32'b0;       // 无写数据

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
    .we_i      (ram_we),
    .be_i      (ram_be),
    .addr_i    (addr_i),
    .wdata_i   (ram_wdata),

    .rvalid_o  (rvalid_o),
    .rdata_o   (rdata_o)
  );

  // ==========================================================================
  // TODO: 可选扩展功能
  // ==========================================================================

  // TODO: 添加指令存储器访问计数 (性能分析用)
  // TODO: 添加总线错误检测 (地址越界检查)
  // TODO: 添加ECC校验逻辑 (可选)
  // TODO: 添加存储器保护 (PMP检查)

endmodule
