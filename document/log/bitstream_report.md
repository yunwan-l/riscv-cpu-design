# Vivado Bitstream 生成报告（最终版）

> 日期：2026-07-08
> 工具：Vivado 2018.3
> 目标器件：Artix-7 xc7a100tcsg324-1 (Nexys4 DDR)
> 顶层模块：rvp_fpga_top

---

## 1. Bitstream 文件信息

| 项目 | 值 |
|------|-----|
| 文件名 | rvp_fpga_top.bit |
| 文件大小 | 452.72 KB (463,583 bytes) |
| 生成时间 | 2026-07-08 17:38:26 |
| 工程路径 | C:/rvp_proj/build/vivado/rvp_nexys4 |
| 源项目 | d:\大学资料\北邮\课程\阶段式程序设计2 |

## 2. 综合与实现结果

| 阶段 | 状态 | Error | Critical Warning | Warning |
|------|------|-------|------------------|---------|
| Synthesis | 完成 | 0 | 0 | 0 |
| Implementation | 完成 | 0 | 0 | 0 |
| Bitstream | 成功 | 0 | — | — |

> 仅 1 个 Vivado 正常行为提示：`[Constraints 18-5210] No constraints selected for write`（综合阶段不写入约束，此为项目模式正常行为，非错误）

## 3. 设计配置

| 项目 | 值 |
|------|-----|
| 器件 | xc7a100tcsg324-1 |
| 配置电压 | 3.3V |
| CFGBVS | VCCO |
| Bitstream 压缩 | 启用 |
| 配置速率 | 50 MHz |

## 4. 时钟架构

| 时钟域 | 频率 | 周期 | 波形 | 用途 |
|--------|------|------|------|------|
| sys_clk_pin | 100 MHz | 10 ns | {0, 5} | 板载晶振 (E3)，驱动数码管刷新 |
| clk_div2 | 50 MHz | 20 ns | {0, 10} | sys_clk_pin 二分频，驱动 SoC/CPU |

## 5. 时序分析（最终）

### 5.1 时钟域内时序

| 时钟域 | 频率 | WNS (ns) | TNS (ns) | Failing Endpoints | Total Endpoints | 结果 |
|--------|------|----------|----------|-------------------|-----------------|------|
| sys_clk_pin | 100 MHz | +6.189 | 0.000 | 0 | 20 | ✅ 通过 |
| clk_div2 | 50 MHz | +15.580 | 0.000 | 0 | 100 | ✅ 通过 |

### 5.2 时钟域间时序

| 路径 | WNS (ns) | Failing Endpoints | 结果 |
|------|----------|-------------------|------|
| 跨时钟域 | — | 0 | ✅ 通过（已设 false_path） |

### 5.3 保持时间

| 时钟域 | WHS (ns) | Failing Endpoints | 结果 |
|--------|----------|-------------------|------|
| sys_clk_pin | +0.311 | 0 | ✅ 通过 |
| clk_div2 | +0.265 | 0 | ✅ 通过 |

**结论：所有时钟域建立/保持时间全部通过，0 时序违例。**

## 6. 资源利用率（最终）

| 资源 | 占用 | 可用 | 占比 |
|------|------|------|------|
| Slice LUTs | 70 | 63,400 | 0.11% |
| Slice Registers | 89 | 126,800 | 0.07% |
| Block RAM | 0 | 135 | 0.00% |
| DSP | 0 | 240 | 0.00% |
| IO | 34 | 210 | 16.19% |

## 7. 引脚分配摘要

| 功能 | 引脚 | 数量 |
|------|------|------|
| 时钟 (clk) | E3 | 1 |
| 复位 (rst_n) | C12 | 1 |
| UART TX | D4 | 1 |
| LED | H17, K15, J13, N14, R18, V17, U17, U16, V16, T15, U14, T16, V15, V14, V12, V11 | 16 |
| 开关 | J15, L16, M13, R15, R17, T18, U18, R13, T8, U8, R16, T13, H6, U12, U11, V10 | 16 |
| 数码管段 | T10, R10, K16, K13, P15, T11, L18 | 7 |
| 数码管位选 | J17, J18, T9, J14, P14, T14, K2, U13 | 8 |
| 按钮 | N17 | 1 |

## 8. 下载方法

1. 连接 Nexys4 DDR 板的 USB 线
2. 打开 Vivado → Hardware Manager
3. Open Target → Auto Connect
4. Right-click XC7A100T → Program Device
5. 选择 rvp_fpga_top.bit → Program

## 9. 源文件清单（18个 SystemVerilog 文件）

```
rtl/rvp_pkg.sv                    - SystemVerilog 包定义
rtl/core/rvp_alu.sv               - 算术逻辑单元
rtl/core/rvp_imm_generator.sv     - 立即数生成器
rtl/core/rvp_register_file.sv     - 寄存器堆
rtl/core/rvp_branch_unit.sv       - 分支判断单元
rtl/core/rvp_decoder.sv           - 指令译码器
rtl/core/rvp_hazard_unit.sv       - 冒险检测单元
rtl/core/rvp_forward_unit.sv      - 前递单元
rtl/core/rvp_multdiv.sv           - 乘除法器
rtl/core/rvp_pipeline_regs.sv     - 流水线寄存器
rtl/core/rvp_instr_mem.sv         - 指令存储器
rtl/core/rvp_data_mem.sv          - 数据存储器
rtl/core/rvp_core_pipeline.sv     - CPU 流水线核心
rtl/periph/rvp_uart.sv            - UART 发送器
rtl/periph/rvp_gpio.sv            - GPIO 控制器
rtl/periph/rvp_timer.sv           - 定时器
rtl/rvp_soc.sv                    - 片上系统
rtl/rvp_fpga_top.sv               - FPGA 顶层封装
```

## 10. 版本历史

| 版本 | 时间 | 变更 |
|------|------|------|
| v1 | 2026-07-08 17:21 | 首次生成，时序违例（数码管 false_path），warning 110+ |
| v2 | 2026-07-08 17:38 | 修复所有 warning，全部时钟域时序通过，0 Error 0 Warning |