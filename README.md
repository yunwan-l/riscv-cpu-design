# riscv-cpu-design

基于 Nexys4 DDR (Artix-7 XC7A100T) 实现 RISC-V (RV32I) 处理器。
直接 5 级流水线 (IF→ID→EX→MEM→WB)，哈佛结构，可选 I-Cache/D-Cache。
拓展方向：Cache 替换策略优化与命中率分析。

参考项目：`document/references/ibex`、`document/references/picorv32`。

---

## 完整目录结构

```
riscv-cpu-design/
├── README.md                      # 本文件 — 项目总览与目录说明
├── Makefile                       # 顶层构建入口 (sim/synth/test/configs/clean)
├── 架构设计方案与系统框图.md       # 架构设计文档 (含 27 张 Mermaid 图)
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
│   │   ├── rvp_imm_generator.sv   #     立即数生成 (I/S/B/U/J/Z)
│   │   ├── rvp_register_file.sv   #     寄存器堆 (2R1W, BRAM)
│   │   ├── rvp_branch_unit.sv     #     分支判定 (6 种条件)
│   │   ├── rvp_decoder.sv          #     译码器 (输出 ctrl_signals_t)
│   │   ├── rvp_controller.sv       #     主 FSM 控制器
│   │   ├── rvp_hazard_unit.sv     #     冒险检测 (load-use stall/flush)
│   │   ├── rvp_forward_unit.sv    #     前递单元 (条件编译)
│   │   ├── rvp_if_stage.sv        #     IF 级 (PC/取指/ICache 接口)
│   │   ├── rvp_id_stage.sv        #     ID 级
│   │   ├── rvp_ex_stage.sv        #     EX 级 (ALU/分支)
│   │   ├── rvp_mem_stage.sv      #     MEM 级 (LSU/对齐)
│   │   ├── rvp_wb_stage.sv        #     WB 级 (写回选择)
│   │   └── rvp_core.sv            #     核心顶层
│   │
│   ├── cache/                     #   Cache 子系统 (7 模块 + 1 包)
│   │   ├── rvp_cache_pkg.sv       #     Cache 参数包
│   │   ├── rvp_cache_tag_array.sv #     Tag 数组
│   │   ├── rvp_cache_data_array.sv#     Data 数组
│   │   ├── rvp_cache_replacement.sv#   替换策略 (RR/LRU/PLRU/FIFO/RAND/SRRIP) ★拓展
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
│       ├── rvp_uart.sv            #     UART 16550
│       ├── rvp_gpio.sv            #     16-bit GPIO
│       └── rvp_timer.sv           #     32-bit 定时器
│
├── soc/                           # SoC 集成 (2 模块)
│   ├── rvp_bus_interconnect.sv    #   总线互连 (优先级仲裁)
│   └── rvp_soc_top.sv             #   SoC 顶层 (CPU+MEM+外设+地址映射)
│
├── tb/                            # 仿真测试
│   ├── rvp_tb.sv                  #   顶层 testbench
│   ├── rvp_test_utils.svh         #   测试宏
│   ├── tb_alu.sv                  #   ALU 单元测试
│   ├── tb_branch_unit.sv         #   分支单元测试
│   ├── tb_core_pipeline.sv       #   流水线核心测试
│   ├── tb_core_single.sv         #   单周期核心测试
│   ├── tb_decoder.sv              #   译码器测试
│   ├── tb_imm_generator.sv       #   立即数生成器测试
│   ├── tb_register_file.sv       #   寄存器堆测试
│   └── tests/
│       ├── Makefile               #     固件编译 (.S → .hex)
│       └── README.md              #     42 个测试用例说明
│
├── synth/                         # 综合
│   └── vivado/
│       ├── create_project.tcl     #     建工程脚本
│       ├── run_synth.tcl          #     综合与报告
│       └── rvp_nexys4.xdc         #     NEXYS4 约束 (clk/UART/GPIO)
│
├── rvp_build.py                   # Python 构建脚本 (Windows/ModelSim)
│
├── document/                      # 文档与参考资料
│   ├── nexys4解释.md
│   └── references/                #   开源参考项目 (只读)
│       ├── ibex/                  #     Ibex (2/3 级流水线, ~21k 行)
│       └── picorv32/              #     PicoRV32 (多周期 FSM, ~2.7k 行)
│
└── riscv-course-analysis/         # 课程要求与项目分析报告
    └── riscv-course-analysis.html
```

## 模块统计

| 类别 | 文件数 | 说明 |
|------|--------|------|
| 包文件 | 2 | `rvp_pkg.sv`, `rvp_cache_pkg.sv` |
| CPU 核心 | 14 | ALU/译码/寄存器堆/5 级流水/冒险/前递/控制器 |
| Cache 子系统 | 7 | 含 6 种替换策略 (拓展重点) |
| 存储器 | 4 | RAM/指令/数据存储器 |
| 外设 | 3 | UART/GPIO/Timer |
| SoC 集成 | 2 | 总线互连 + SoC 顶层 |
| 测试 | 4 | testbench + 测试宏 + Makefile + 说明 |
| 综合 | 3 | Tcl 脚本 + 约束 |
| 配置 | 3 | 宏配置 + 命名配置 + 文件清单 |
| **合计** | **42** | (不含 document/references) |

## 三阶段开发路线

1. **Phase 1 — 基础流水线**：`phase1_basic` 配置，RV32I 子集，单周期取指，无 Cache
2. **Phase 2 — 完整 SoC**：`phase2_full_rv32i` 配置，完整 RV32I + 外设 + 内存
3. **Phase 3 — Cache 拓展**：`phase3_icache_*` 配置，6 种替换策略对比分析

> Phase 1 & 2 核心模块已完成实现。用 `py rvp_build.py sim -c phase2_full_rv32i -f <固件.hex>` 运行仿真。
