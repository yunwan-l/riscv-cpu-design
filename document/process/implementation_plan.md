# 进阶任务实施计划 — 完整可运行SoC系统集成

## 任务要求

在基础CPU基础上集成内存与I/O接口，构建完整可运行系统：
1. 完成CPU、内存子系统与基本I/O接口的系统集成
2. 能够支持小型测试程序的完整运行
3. 分析系统性能瓶颈并提出优化方案
4. 引入流水线机制，对时钟频率、CPI与吞吐量进行量化评估

## 目标平台

| 项目 | 规格 |
|------|------|
| FPGA开发板 | Digilent Nexys4 DDR |
| FPGA芯片 | Artix-7 XC7A100T-1CSG324C |
| 板载时钟 | 100MHz (引脚E3) |
| 综合工具 | Vivado 2018 |
| 仿真工具 | ModelSim SE-64 10.7 |
| 逻辑资源 | 15,850 Slices (63,400 LUT) |
| BRAM | 4,860 Kbits (135个36Kb块) |
| DSP | 240个DSP48E1切片 |

## 当前项目状态

### 已完成

| 模块 | 说明 |
|------|------|
| 5级流水线CPU | rvp_core_pipeline.sv，前递+Load-Use冒险+分支冲刷 |
| SoC集成 | rvp_soc.sv，CPU+RAM+UART+GPIO+Timer，同步写+异步读总线 |
| M扩展 | rvp_multdiv.sv，8条乘除法指令 |
| RV32I自检 | 45项riscv-tests全部通过 |
| I/O外设 | UART(TX)/GPIO(16位LED+SW)/Timer |
| 仿真环境 | 10个testbench + wave.do脚本 + run_all_tests.ps1回归脚本 |

### 仿真测试结果

10项仿真测试全部通过，包括SoC集成测试11项全PASS（GPIO/UART/Timer验证）。

## Nexys4 DDR引脚对照检查

### 官方XDC引脚分配 (Digilent Nexys-4-DDR-Master.xdc)

| 信号 | 引脚 | 说明 |
|------|------|------|
| CLK100MHZ | E3 | 100MHz晶体振荡器 |
| CPU_RESETN | C12 | CPU复位按钮（低有效） |
| UART_TXD_IN | C4 | FPGA接收数据（FPGA的RX） |
| UART_RXD_OUT | D4 | FPGA发送数据（FPGA的TX） |
| LED[0:15] | H17,K15,J13,N14,R18,V17,U17,U16,V16,T15,U14,T16,V15,V14,V12,V11 | 16个用户LED |
| SW[0:15] | J15,L16,M13,R15,R17,T18,U18,R13,T8,U8,R16,T13,H6,U12,U11,V10 | 16个拨码开关 |
| CA-CG | T10,R10,K16,K13,P15,T11,L18 | 七段数码管段（active low） |
| AN[0:7] | J17,J18,T9,J14,P14,T14,K2,U13 | 七段数码管位选（active low） |
| BTNC | N17 | 中心按钮（active high） |

### 发现的问题

**问题1：UART引脚分配错误（阻断）**

项目现有XDC中UART引脚为B18/B19，但这两个引脚在官方XDC中属于JXADC扩展接口（XA_P[4]/XA_N[4]），并非UART引脚。

- 现有（错误）：uart_tx=B18, uart_rx=B19
- 官方XDC：FPGA TX=D4 (UART_RXD_OUT), FPGA RX=C4 (UART_TXD_IN)
- 修正方案：uart_tx改为D4，删除uart_rx约束（SoC当前无RX功能）

**问题2：文件列表过时（阻断）**

`config/rvp_core.f` 仍引用旧架构文件，与当前SoC架构不匹配：
- 包含已废弃的 `rvp_core.sv`、`soc/rvp_soc_top.sv`、`soc/rvp_bus_interconnect.sv`
- 包含当前不使用的Cache模块
- 缺少 `rvp_core_pipeline.sv`、`rvp_pipeline_regs.sv`、`rvp_multdiv.sv`、`rvp_soc.sv`
- `rtl/core/` 和 `rtl/mem/` 下存在同名但不同实现的存储器文件，同时包含会导致重复定义

**问题3：综合脚本top模块错误（阻断）**

`create_project.tcl` 默认 top=rvp_core，应为 rvp_fpga_top。

**问题4：SoC缺少七段数码管接口**

`rvp_soc.sv` 没有seg/an端口，需要在FPGA顶层wrapper中添加七段数码管动态扫描模块。

**问题5：配置大小写不匹配（次要）**

YAML键名 `Forwarding` 经TCL脚本映射为 `RVP_Forwarding`，但代码中使用 `RVP_FORWARDING`。当前phase2配置中Forwarding=0，不影响阶段一。

## 实施计划

### 阶段1：FPGA综合适配（2-3天）

**目标**：使项目能在Vivado 2018中成功综合并生成bitstream，在Nexys4 DDR上板运行。

#### 1a. 创建FPGA顶层wrapper (rvp_fpga_top.sv)

创建 `rtl/rvp_fpga_top.sv`，功能：
- 端口名匹配XDC约束（clk, rst_n, uart_tx, led[15:0], sw[15:0], btn_center, seg_ca-cg, an[7:0]）
- 内部例化 `rvp_soc`
- 添加七段数码管动态扫描模块，显示PC值低32位（8个十六进制数字）
  - 分频计数器：100MHz / 1kHz = 100,000分频（17位计数器）
  - 位选计数器：3位，0-7循环
  - 十六进制段码查找表（共阳极，active low）
  - 段排列：CA(顶), CB(右上), CC(右下), CD(底), CE(左下), CF(左上), CG(中)

七段数码管段码表（CA-CG，active low，0=亮）：

| 数字 | 段码(二进制 CG-CF-CE-CD-CC-CB-CA) | 十六进制 |
|------|-----------------------------------|----------|
| 0 | 1100000 | 0xC0 |
| 1 | 1111001 | 0xF9 |
| 2 | 0100100 | 0xA4 |
| 3 | 0110000 | 0xB0 |
| 4 | 0011001 | 0x19 |
| 5 | 0010010 | 0x12 |
| 6 | 0000010 | 0x02 |
| 7 | 1111000 | 0x78 |
| 8 | 0000000 | 0x00 |
| 9 | 0010000 | 0x10 |
| A | 0001000 | 0x08 |
| b | 0000011 | 0x03 |
| C | 1000110 | 0x46 |
| d | 0100001 | 0x21 |
| E | 0000110 | 0x06 |
| F | 0001110 | 0x0E |

注意：以上段码为CA在bit0，CG在bit6的编码。实际实现时需根据XDC引脚顺序调整。

#### 1b. 修正XDC约束文件 (rvp_nexys4.xdc)

修改内容：
- uart_tx引脚从B18改为D4（官方UART_RXD_OUT）
- 删除uart_rx约束（SoC无RX功能）
- 时钟引脚E3（不变，正确）
- 复位引脚C12（不变，正确）
- LED/SW引脚（不变，正确）
- 七段数码管引脚（不变，正确）
- btn_center引脚N17（不变，正确）

#### 1c. 修正文件列表 (rvp_core.f)

更新为当前SoC架构所需的文件列表：

```
// 1. 包
rtl/rvp_pkg.sv

// 2. 核心叶子模块
rtl/core/rvp_alu.sv
rtl/core/rvp_imm_generator.sv
rtl/core/rvp_register_file.sv
rtl/core/rvp_branch_unit.sv
rtl/core/rvp_decoder.sv
rtl/core/rvp_hazard_unit.sv
rtl/core/rvp_forward_unit.sv
rtl/core/rvp_multdiv.sv
rtl/core/rvp_pipeline_regs.sv

// 3. 存储器（使用rtl/core/版本）
rtl/core/rvp_instr_mem.sv
rtl/core/rvp_data_mem.sv

// 4. CPU核心顶层
rtl/core/rvp_core_pipeline.sv

// 5. 外设
rtl/periph/rvp_uart.sv
rtl/periph/rvp_gpio.sv
rtl/periph/rvp_timer.sv

// 6. SoC
rtl/rvp_soc.sv

// 7. FPGA顶层
rtl/rvp_fpga_top.sv
```

不包含的文件：
- rtl/cache/* （当前不使用Cache）
- rtl/core/rvp_core.sv （旧CPU核心）
- rtl/core/rvp_core_single.sv （单周期版本）
- rtl/core/rvp_controller.sv （旧控制器）
- rtl/core/rvp_if_stage.sv, rvp_id_stage.sv, rvp_ex_stage.sv, rvp_mem_stage.sv, rvp_wb_stage.sv （旧流水线阶段）
- rtl/mem/* （使用rtl/core/下的版本避免重复定义）
- soc/* （旧SoC文件）

#### 1d. 修正综合脚本 (create_project.tcl)

- 默认top模块从 `rvp_core` 改为 `rvp_fpga_top`
- 默认配置保持 `phase2_full_rv32i`（RV32M=1，无Cache，无前递）

#### 1e. Vivado综合验证

- 运行 `vivado -mode batch -source create_project.tcl`
- 检查综合报告：LUT/FF/BRAM资源占用
- 检查时序报告：Fmax（目标≥50MHz）
- 生成bitstream

### 阶段2：性能量化评估（2-3天）

#### 2a. 添加性能计数器

在 `rvp_core_pipeline.sv` 中添加5个32位计数器：
- `inst_retired`：完成指令数（WB阶段每完成一条指令+1）
- `cycle_count`：总周期数（每个时钟周期+1）
- `stall_count`：Load-Use停顿数
- `flush_count`：分支冲刷数
- `branch_count`：分支指令数

通过MMIO寄存器映射到SoC地址空间（如0x10030000），或通过testbench直接读取。

#### 2b. 编写性能测试程序

用RISC-V汇编编写3种典型程序：
- 矩阵乘法（计算密集型）
- 冒泡排序（分支密集型）
- 斐波那契递归（控制流密集型）

#### 2c. CPI计算

CPI = cycle_count / inst_retired
理想CPI = 1.0
实际CPI = 1.0 + stall惩罚 + flush惩罚

#### 2d. Fmax测量

Vivado综合后的时序报告给出最大时钟频率。

#### 2e. 吞吐量计算

Throughput = Fmax / CPI（单位MIPS）

### 阶段3：瓶颈分析与优化方案（2-3天）

#### 3a. CPI分解

将CPI分解为：
- 理想CPI（1.0）
- Load-Use冒险惩罚（stall_count / inst_retired）
- 分支冲刷惩罚（flush_count × 2 / cycle_count）

#### 3b. 数据冒险分析

stall_count / inst_retired 给出Load-Use冒险频率，分析哪些指令序列导致停顿。

#### 3c. 控制冒险分析

flush_count × 2 / cycle_count 给出分支惩罚占比，分析分支跳转率。

#### 3d. 优化方案

- 分支预测：当前分支在EX级判定，跳转惩罚2周期。可改为ID级判定（惩罚降为1周期），或添加2-bit饱和预测器
- 指令调度：编译器层面在Load和依赖指令间插入独立指令，减少stall
- Cache影响分析：当前IMEM/DMEM均为1周期异步读，分析加入Cache后的命中率与缺失惩罚对CPI的影响

#### 3e. 生成性能评估报告

包含CPI分解表、Fmax/资源表、优化前后对比。

## 工具链注意事项

### Vivado 2018 + ModelSim SE 10.7联合仿真

1. Vivado中Tools → Compile Simulation Libraries，选择ModelSim Simulator
2. 编译Xilinx仿真库到指定目录
3. Vivado 2018支持ModelSim SE 10.7作为第三方仿真器

### ModelSim 10.7特性

- 不支持 `wave delete all` 命令（已在wave_soc.do中注释）
- GUI模式必须加 `-voptargs="+acc"` 防止信号被优化隐藏

### Nexys4 DDR规格

- Artix-7 XC7A100T-1CSG324C
- 100MHz板载时钟（引脚E3）
- 15,850逻辑片，4,860Kbits BRAM，240个DSP切片
- USB-UART桥：FTDI FT2232HQ，FPGA TX=D4，FPGA RX=C4
- CPU RESET按钮：低有效（引脚C12）
- 16个用户LED：高有效（330欧姆限流）
- 16个拨码开关
- 8位七段数码管：共阳极，段和位选均active low

## 风险评估

| 风险 | 影响 | 应对 |
|------|------|------|
| 七段数码管动态扫描时序 | 显示闪烁 | 分频到1kHz，利用视觉暂留 |
| 指令存储器异步读综合 | 可能推断为分布式RAM | Artix-7 BRAM支持异步读，资源充足 |
| UART波特率不匹配 | 串口无输出 | 配置为115200波特率，100MHz/(115200*16)≈54分频 |
| 复位抖动 | 系统不稳定 | Nexys4 CPU RESET按钮已有硬件去抖 |
