# 测试4：Load-Use 冒险（Load-Use Hazard）

## 验证目的

验证 CPU 流水线的 **Load-Use 冒险检测与停顿机制**。当一条 Load 指令（lw）紧接一条使用加载结果的指令时，由于 Load 数据在 MEM 阶段才就绪，无法通过 EX/MEM 前递解决，必须停顿一拍（stall）。

## 固件文件

`firmware_loaduse.hex`（14 条指令）

## 伪代码

```
GPIO_BASE = 0x10010000        # lui x5, 0x10010
value = 0xAA                 # addi x1, x0, 0xAA

loop:
    RAM[0] = value            # sw x1, 0(x0)    → 写入数据存储器
    x2 = RAM[0]               # lw x2, 0(x0)   → 从存储器加载
    x3 = x2 + 0               # addi x3, x2, 0 ← Load-Use 冒险！需要停顿 1 周期
    GPIO[0] = x3              # sw x3, 0(x5)    → 输出 x3 到 LED

    delay(1048576)            # ~252ms
    GPIO[0] = 0               # LED 灭
    delay(1048576)            # ~252ms

    goto loop                 # jal 0x04
```

## 汇编指令详解

| 地址 | 指令 | 说明 |
|------|------|------|
| 0x00 | `lui x5, 0x10010` | x5 = 0x10010000 (GPIO 基地址) |
| 0x04 | `addi x1, x0, 0xAA` | x1 = 170 (0xAA = 10101010) |
| 0x08 | `sw x1, 0(x0)` | RAM[0] = 0xAA (写入数据存储器) |
| 0x0C | `lw x2, 0(x0)` | x2 = RAM[0] (从存储器加载) |
| 0x10 | `addi x3, x2, 0` | x3 = x2 ← **Load-Use 冒险** |
| 0x14 | `sw x3, 0(x5)` | GPIO = x3 (输出到 LED) |
| 0x18 | `lui x10, 0x100` | 延迟计数器 = 1048576 |
| 0x1C | `addi x10, x10, -1` | 延迟循环 |
| 0x20 | `bnez x10, -4` | 循环 |
| 0x24 | `sw x0, 0(x5)` | GPIO = 0 (LED 灭) |
| 0x28 | `lui x10, 0x100` | 延迟计数器 = 1048576 |
| 0x2C | `addi x10, x10, -1` | 延迟循环 |
| 0x30 | `bnez x10, -4` | 循环 |
| 0x34 | `j 0x04` | 跳回循环开始 |

## 关键点

- **Load-Use 冒险检测**：`rvp_hazard_unit.sv` 检测 `ex_ctrl.mem_read=1` 且 `ex_ctrl.rd_addr == id_ctrl.rs1_addr`，输出 `stall=1`
- **停顿行为**：PC 冻结、IF/ID 冻结、ID/EX 插入 NOP（气泡），1 周期后 Load 数据通过 MEM/WB 前递到达
- **数据存储器**：Data RAM 地址 0x00000000，`rvp_data_mem.sv` 异步读
- **GPIO 读回**：此处实际是 RAM 读写测试（sw 到 RAM 地址 0，lw 从 RAM 地址 0 读回），不是 GPIO 读回
- **延迟时间**：1048576 × 3 × 80ns ≈ 252ms，闪烁频率约 2Hz
- **x5 保护**：延迟用 x10，不破坏 x5 的 GPIO 基地址

## 流水线时序

```
周期  IF     ID        EX        MEM       WB
T1    lw     ...       ...       ...       ...
T2    addi   lw        ...       ...       ...    ← hazard 检测：lw.rd == addi.rs1
T3    addi   NOP(气泡) lw        ...       ...    ← stall! ID/EX 插入 NOP
T4    sw     addi      NOP(气泡) lw        ...    ← lw 数据在 MEM 就绪
T5    ...    sw         addi     NOP(气泡)  lw    ← MEM/WB 前递 x2 给 addi
```

## 预期结果

| 观察项 | 预期 |
|--------|------|
| LED[7:0] | 1/3/5/7 号灯亮（0xAA = 10101010），约 2Hz 闪烁 |
| LED[15:8] | 始终熄灭 |
| 数码管（LED 亮时） | 0x1C / 0x20 / 0x24 交替 |
| 数码管（LED 灭时） | 0x2C / 0x30 / 0x34 交替 |
| 串口 | 无输出 |

## 通过标准

- **LED 1、3、5、7 一起闪烁**（0xAA 模式）
- 如果 Load-Use stall 有 Bug，x3 会拿到错误值（0 或垃圾值），LED 不会显示 0xAA

## 失败排查

| 现象 | 可能原因 |
|------|---------|
| LED 全灭 | Load-Use stall 未触发，x2=0，x3=0 |
| LED 全亮 | Load-Use stall 逻辑错误，读到垃圾值 |
| LED 显示 0xAA 但不闪烁 | 延迟循环错误 |
| LED 显示非 0xAA | 数据存储器读写错误 |

## 实际测试结果

在硬件上下载固件后，观察到 LED 1/3/5/7 以约 2Hz 频率闪烁（0xAA = 10101010 模式），LED 8~15 始终熄灭。这表明 Load-Use 冒险检测与停顿机制工作正常：lw 指令加载的数据 0xAA 经过 1 周期 stall 后通过 MEM/WB 前递正确送达后续 addi 指令，最终输出到 LED 的值为 0xAA。

| 观察项 | 实际结果 |
|--------|----------|
| LED[7:0] | 1/3/5/7 号灯亮（0xAA 模式），约 2Hz 闪烁 |
| LED[15:8] | 始终熄灭 |
| Load-Use stall | 正确触发，x2=0xAA 成功前递给 addi |

**测试结果：PASS**
