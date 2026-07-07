# riscv-cpu-design

基于 Nexys4 DDR (Artix-7 XC7A100T) 实现 RISC-V (RV32IM) 处理器。
5 级流水线 (IF→ID→EX→MEM→WB)，哈佛结构，含完整 SoC 集成与 M 扩展。
拓展方向：Cache 替换策略优化与命中率分析。

参考项目：`document/references/ibex`、`document/references/picorv32`。

---

## 目录结构

```
riscv-cpu-design/
├── README.md                      # 本文件 — 项目总览与目录说明
├── Makefile                       # 顶层构建入口 (sim/synth/test/configs/clean)
├── 架构设计方案与系统框图.md       # 架构设计文档 (含 Mermaid 图)
│
├── config/                        # 编译期配置
│   ├── rvp_config.svh             #   全局宏配置 (ISA/流水线/Cache/外设)
│   ├── rvp_configs.yaml            #   9 个命名配置 (phase1/2/3-*)
│   └── rvp_core.f                  #   RTL 文件清单 (编译顺序)
│
├── rtl/                           # RTL 源码
│   ├── rvp_pkg.sv                 #   全局包 (opcodes/ALU/控制信号/FSM)
│   │
│   ├── core/                      #   CPU 核心 (14 个模块)
│   │   ├── rvp_alu.sv             #     ALU (RV32I + M 扩展)
│   │   ├── rvp_imm_generator.sv   #     立即数生成 (I/S/B/U/J)
│   │   ├── rvp_register_file.sv   #     寄存器堆 (2R1W, BRAM)
│   │   ├── rvp_branch_unit.sv     #     分支判定 (6 种条件)
│   │   ├── rvp_decoder.sv          #     译码器 (输出 ctrl_t)
│   │   ├── rvp_controller.sv     #     主 FSM 控制器
│   │   ├── rvp_hazard_unit.sv     #     冒险检测 (load-use stall/flush)
│   │   ├── rvp_forward_unit.sv    #     前递单元 (EX/MEM → EX)
│   │   ├── rvp_if_stage.sv        #     IF 级 (PC/取指/ICache 接口)
│   │   ├── rvp_id_stage.sv        #     ID 级 (译码/寄存器读/立即数)
│   │   ├── rvp_ex_stage.sv        #     EX 级 (ALU/分支/M 扩展)
│   │   ├── rvp_mem_stage.sv      #     MEM 级 (LSU/对齐)
│   │   ├── rvp_wb_stage.sv        #     WB 级 (写回选择)
│   │   ├── rvp_core.sv            #     流水线核心顶层
│   │   └── rvp_core_single.sv    #     单周期核心 (Phase 1 验证用)
│   │
│   ├── cache/                     #   Cache 子系统 (7 模块 + 1 包)
│   │   ├── rvp_cache_pkg.sv       #     Cache 参数包
│   │   ├── rvp_cache_tag_array.sv #     Tag 数组
│   │   ├── rvp_cache_data_array.sv#     Data 数组
│   │   ├── rvp_cache_replacement.sv#   替换策略 (RR/LRU/PLRU/FIFO/RAND/SRRIP)
│   │   ├── rvp_cache_stats.sv    #     命中率统计
│   │   ├── rvp_cache_flush.sv    #     刷写/无效化
│   │   ├── rvp_icache.sv          #     I-Cache (2-way, 4KB)
│   │   └── rvp_dcache.sv          #     D-Cache (write-back)
│   │
│   ├── mem/                       #   存储器 (4 模块)
│   │   ├── rvp_ram_1p.sv          #     单口 RAM
│   │   ├── rvp_ram_2p.sv          #     双口 RAM
│   │   ├── rvp_instr_mem.sv      #     指令存储器 (32KB BRAM)
│   │   └── rvp_data_mem.sv        #     数据存储器 (32KB BRAM)
│   │
│   └── periph/                    #   外设 (3 模块)
│       ├── rvp_uart.sv            #     UART (8-N-1, 波特率可配)
│       ├── rvp_gpio.sv            #     16-bit GPIO (输入/输出/方向)
│       └── rvp_timer.sv           #     32-bit 定时器 (使能/重载/比较)
│
├── soc/                           # SoC 集成 (2 模块)
│   ├── rvp_bus_interconnect.sv    #   总线互连 (地址译码 + 优先级仲裁)
│   └── rvp_soc_top.sv             #   SoC 顶层 (CPU+MEM+外设+地址映射)
│
├── sw/                            # 测试固件 (汇编)
│   ├── lib/
│   │   └── rvp_test_macros.h      #   自有测试宏
│   └── tests/
│       ├── link.ld                #   链接脚本
│       ├── rv32ui_p_all.S         #   RV32I 全指令自检 (242 条)
│       └── soc_test.S             #   SoC 集成测试 (GPIO/UART/Timer)
│
├── tb/                            # 仿真测试
│   ├── rvp_tb.sv                  #   顶层 SoC testbench
│   ├── rvp_test_utils.svh         #   测试宏定义
│   ├── run_all_tests.ps1          #   一键回归测试脚本 (PowerShell)
│   │
│   │   # --- 单元测试 (9 个) ---
│   ├── tb_alu.sv                  #   ALU 单元测试 (32 cases)
│   ├── tb_branch_unit.sv          #   分支单元测试 (4 cases)
│   ├── tb_decoder.sv              #   译码器测试 (39 cases)
│   ├── tb_imm_generator.sv       #   立即数生成器测试 (11 cases)
│   ├── tb_register_file.sv       #   寄存器堆测试
│   ├── tb_multdiv.sv              #   M 扩展乘除法测试 (34 cases)
│   ├── tb_core_single.sv         #   单周期 CPU 集成测试 (11 cases)
│   ├── tb_core_pipeline.sv       #   流水线核心测试
│   ├── tb_rv32ui_p_all.sv         #   RV32I 全指令自检测试
│   ├── tb_soc.sv                  #   SoC 集成测试 (11 cases)
│   │
│   │   # --- 波形配置脚本 (.do) ---
│   ├── wave_alu.do                #   ALU 波形配置
│   ├── wave_branch.do             #   分支单元波形配置
│   ├── wave_decoder.do            #   译码器波形配置
│   ├── wave_imm.do                #   立即数生成器波形配置
│   ├── wave_multdiv.do            #   乘除法波形配置
│   ├── wave_regfile.do            #   寄存器堆波形配置
│   ├── wave_single.do             #   单周期 CPU 波形配置
│   ├── wave_pipeline.do           #   流水线 CPU 波形配置
│   ├── wave_rv32ui.do             #   RV32I 自检波形配置
│   ├── wave_soc.do                #   SoC 集成波形配置
│   │
│   └── tests/
│       ├── Makefile               #   固件编译 (.S → .hex)
│       └── README.md              #   42 个测试用例说明
│
├── synth/                         # Vivado 综合
│   └── vivado/
│       ├── create_project.tcl     #   建工程脚本
│       ├── run_synth.tcl          #   综合与报告
│       └── rvp_nexys4.xdc         #   NEXYS4 DDR 约束
│
├── rvp_build.py                   # Python 构建脚本 (Windows/ModelSim)
│
└── document/                      # 文档与参考资料
    ├── nexys4解释.md
    ├── modelsim-sim-tutorial.html #   ModelSim 仿真教程
    └── references/               #   开源参考项目 (只读)
        ├── ibex/                  #     Ibex (2/3 级流水线, ~21k 行)
        └── picorv32/              #     PicoRV32 (多周期 FSM, ~2.7k 行)
```

## 模块统计

| 类别 | 文件数 | 说明 |
|------|--------|------|
| 包文件 | 2 | `rvp_pkg.sv`, `rvp_cache_pkg.sv` |
| CPU 核心 | 15 | ALU/译码/寄存器堆/5 级流水/单周期/冒险/前递/控制器 |
| Cache 子系统 | 7 | 含 6 种替换策略 (拓展重点) |
| 存储器 | 4 | RAM/指令/数据存储器 |
| 外设 | 3 | UART/GPIO/Timer |
| SoC 集成 | 2 | 总线互连 + SoC 顶层 |
| 测试 | 22 | 10 个 testbench + 10 个 .do 波形脚本 + 2 个工具 |
| 测试固件 | 3 | 2 个汇编测试程序 + 链接脚本 |
| 综合 | 3 | Tcl 脚本 + XDC 约束 |
| 配置 | 3 | 宏配置 + 命名配置 + 文件清单 |
| **合计** | **64** | (不含 document/references) |

## 三阶段开发路线

1. **Phase 1 — 基础**：`phase1_basic`，单周期 CPU，RV32I 子集，单元测试全通过
2. **Phase 2 — 完整 SoC**：`phase2_full_rv32i`，5 级流水线 + 前递 + 冒险处理 + M 扩展 + SoC 集成
3. **Phase 3 — Cache 拓展**：`phase3_icache_*`，6 种替换策略对比分析

## 仿真与测试

### 快速开始 (ModelSim)

```powershell
# 单个模块测试
cd tb
vsim -voptargs="+acc" -do wave_alu.do -lib work tb_alu

# SoC 集成测试
vsim -voptargs="+acc" -do wave_soc.do -lib work tb_soc

# 一键回归测试
..\tb\run_all_tests.ps1
```

### 测试覆盖

| 测试 | 用例数 | 状态 |
|------|--------|------|
| ALU | 32 | PASS |
| 立即数生成器 (I/S/B/U/J) | 11 | PASS |
| 译码器 (39 种指令) | 39 | PASS |
| 分支单元 | 4 | PASS |
| 寄存器堆 | - | PASS |
| M 扩展乘除法 (含除零/溢出) | 34 | PASS |
| 单周期 CPU 集成 | 11 | PASS |
| 流水线 CPU | - | PASS |
| RV32I 全指令自检 (242 条) | - | PASS |
| SoC 集成 (GPIO/UART/Timer) | 11 | PASS |

### SoC 地址映射

| 地址范围 | 外设 |
|----------|------|
| `0x0000_0000` | 指令存储器 (32KB) |
| `0x0001_0000` | 数据存储器 (32KB) |
| `0x1000_0000` | UART |
| `0x1001_0000` | GPIO |
| `0x1002_0000` | Timer |

### 固件编译

```bash
cd tb/tests
make all          # 编译所有测试
make test_add     # 编译单个测试
```
