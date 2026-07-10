/**
 * rvp_bus_interconnect.sv - Bus Interconnect / Address Decoder
 *
 * RVP SoC的总线互连模块，连接CPU数据端口到各从设备。
 * 实现主机优先级仲裁和基于掩码的地址译码。
 *
 * 参考: ibex shared/rtl/bus.sv (136行)
 *
 * 功能:
 *   - 多主机优先级仲裁 (编号大的主机优先级高)
 *   - 基于掩码的地址译码 (addr & mask == base)
 *   - 1周期响应延迟
 *   - 地址解码错误检测
 *
 * 简化假设 (与ibex bus.sv相同):
 *   - 所有从设备在请求后1周期响应
 *   - 主机仲裁为固定优先级
 *
 * 地址译码原理:
 *   对于地址A，设备D匹配条件: (A & cfg_device_addr_mask[D]) == cfg_device_addr_base[D]
 *   其中mask为地址范围掩码 (~size + 1)
 *
 * 使用场景:
 *   - 连接CPU数据端口(host)到数据存储器、UART、GPIO、Timer等从设备
 *   - 指令存储器通常直接连接，不经过总线互连
 */

`include "rvp_config.svh"

module rvp_bus_interconnect #(
    /// 从设备(奴隶)数量
    parameter int NrDevices    = 4,
    /// 主设备(主机)数量
    parameter int NrHosts      = 1,
    /// 数据位宽
    parameter int DataWidth    = 32,
    /// 地址位宽
    parameter int AddressWidth = 32
) (
    input  logic                       clk_i,           // 时钟
    input  logic                       rst_ni,          // 异步低有效复位

    // ==========================================================================
    // 主机端口 (Hosts / Masters)
    // ==========================================================================
    input  logic                       host_req_i    [NrHosts],     // 主机请求
    output logic                       host_gnt_o    [NrHosts],     // 主机授权

    input  logic [AddressWidth-1:0]    host_addr_i   [NrHosts],     // 主机地址
    input  logic                       host_we_i     [NrHosts],     // 主机写使能
    input  logic [ DataWidth/8-1:0]    host_be_i     [NrHosts],     // 主机字节使能
    input  logic [   DataWidth-1:0]    host_wdata_i  [NrHosts],     // 主机写数据
    output logic                       host_rvalid_o [NrHosts],     // 主机读有效
    output logic [   DataWidth-1:0]    host_rdata_o  [NrHosts],     // 主机读数据
    output logic                       host_err_o    [NrHosts],     // 主机错误

    // ==========================================================================
    // 从设备端口 (Devices / Slaves)
    // ==========================================================================
    output logic                       device_req_o    [NrDevices],  // 从设备请求

    output logic [AddressWidth-1:0]    device_addr_o   [NrDevices],  // 从设备地址
    output logic                       device_we_o     [NrDevices],  // 从设备写使能
    output logic [ DataWidth/8-1:0]    device_be_o     [NrDevices],  // 从设备字节使能
    output logic [   DataWidth-1:0]    device_wdata_o  [NrDevices],  // 从设备写数据
    input  logic                       device_rvalid_i [NrDevices],  // 从设备读有效
    input  logic [   DataWidth-1:0]    device_rdata_i  [NrDevices],  // 从设备读数据
    input  logic                       device_err_i    [NrDevices],  // 从设备错误

    // ==========================================================================
    // 地址映射配置
    // ==========================================================================
    input  logic [AddressWidth-1:0]    cfg_device_addr_base [NrDevices],  // 设备基地址
    input  logic [AddressWidth-1:0]    cfg_device_addr_mask [NrDevices]   // 设备地址掩码
);

  // ==========================================================================
  // 本地参数
  // ==========================================================================

  // 主机选择信号位宽
  localparam int unsigned NumBitsHostSel   = (NrHosts   > 1) ? $clog2(NrHosts)   : 1;
  // 从设备选择信号位宽
  localparam int unsigned NumBitsDeviceSel = (NrDevices > 1) ? $clog2(NrDevices) : 1;

  // ==========================================================================
  // 内部信号
  // ==========================================================================

  // 主机仲裁结果
  logic                       host_sel_valid;     // 有主机请求
  logic [NumBitsHostSel-1:0]  host_sel_req;       // 选中的主机(请求阶段)
  logic [NumBitsHostSel-1:0]  host_sel_resp;      // 选中的主机(响应阶段)

  // 设备译码结果
  logic                       device_sel_valid;   // 有设备匹配
  logic [NumBitsDeviceSel-1:0] device_sel_req;    // 选中的设备(请求阶段)
  logic [NumBitsDeviceSel-1:0] device_sel_resp;   // 选中的设备(响应阶段)

  // 地址译码错误
  logic                       decode_err_resp;    // 响应阶段的译码错误

  // ==========================================================================
  // 主机优先级仲裁器
  // ==========================================================================

  // 固定优先级: 编号大的主机优先级高
  // 遍历所有主机，选最后一个有请求的
  always_comb begin
    host_sel_valid = 1'b0;
    host_sel_req   = '0;
    for (int host = NrHosts - 1; host >= 0; host--) begin
      if (host_req_i[host]) begin
        host_sel_valid = 1'b1;
        host_sel_req   = NumBitsHostSel'(host);
      end
    end
  end

  // ==========================================================================
  // 设备地址译码器
  // ==========================================================================

  // 基于掩码匹配: (addr & mask) == base
  always_comb begin
    device_sel_valid = 1'b0;
    device_sel_req   = '0;
    for (int device = 0; device < NrDevices; device++) begin
      if ((host_addr_i[host_sel_req] & cfg_device_addr_mask[device])
          == cfg_device_addr_base[device]) begin
        device_sel_valid = 1'b1;
        device_sel_req   = NumBitsDeviceSel'(device);
      end
    end
  end

  // ==========================================================================
  // 响应阶段寄存器 (延迟1周期)
  // ==========================================================================

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      host_sel_resp   <= '0;
      device_sel_resp <= '0;
      decode_err_resp <= 1'b0;
    end else begin
      // 响应在请求后1周期
      host_sel_resp   <= host_sel_req;
      device_sel_resp <= device_sel_req;
      // 译码错误: 有请求但无设备匹配
      decode_err_resp <= host_sel_valid & ~device_sel_valid;
    end
  end

  // ==========================================================================
  // 从设备请求路由
  // ==========================================================================

  // 将选中的主机请求路由到选中的从设备
  always_comb begin
    for (int device = 0; device < NrDevices; device++) begin
      if (device_sel_valid && NumBitsDeviceSel'(device) == device_sel_req) begin
        // 匹配的设备: 路由主机信号
        device_req_o[device]   = host_req_i[host_sel_req];
        device_we_o[device]    = host_we_i[host_sel_req];
        device_addr_o[device]  = host_addr_i[host_sel_req];
        device_wdata_o[device] = host_wdata_i[host_sel_req];
        device_be_o[device]    = host_be_i[host_sel_req];
      end else begin
        // 不匹配的设备: 信号置零
        device_req_o[device]   = 1'b0;
        device_we_o[device]    = 1'b0;
        device_addr_o[device]  = '0;
        device_wdata_o[device] = '0;
        device_be_o[device]    = '0;
      end
    end
  end

  // ==========================================================================
  // 主机响应路由
  // ==========================================================================

  // 将选中从设备的响应路由回选中的主机
  always_comb begin
    for (int host = 0; host < NrHosts; host++) begin
      host_gnt_o[host]    = 1'b0;
      if (NumBitsHostSel'(host) == host_sel_resp) begin
        // 匹配的主机: 路由设备响应
        host_rvalid_o[host] = device_rvalid_i[device_sel_resp] | decode_err_resp;
        host_err_o[host]    = device_err_i[device_sel_resp]    | decode_err_resp;
        host_rdata_o[host]  = device_rdata_i[device_sel_resp];
      end else begin
        // 不匹配的主机: 无响应
        host_rvalid_o[host] = 1'b0;
        host_err_o[host]    = 1'b0;
        host_rdata_o[host]  = '0;
      end
    end
    // 授权: 当前请求阶段选中的主机获得授权
    host_gnt_o[host_sel_req] = host_req_i[host_sel_req];
  end

  // ==========================================================================
  // TODO: 可选扩展功能
  // ==========================================================================

  // TODO: 添加轮询(round-robin)仲裁模式 (可选)
  // TODO: 添加总线流水线支持 (outstanding transactions)
  // TODO: 添加AXI-Lite协议支持 (替代简单总线协议)
  // TODO: 添加地址范围重叠检测断言

endmodule
