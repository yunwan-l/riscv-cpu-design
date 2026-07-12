# 测试8：乘除法扩展（M-Extension）—— UART 输出

## 验证目的

验证 RISC-V M 扩展的**乘除法指令**：MUL、MULH、DIV、DIVU、REM、REMU。通过 UART 输出运算结果，验证 `rvp_multdiv.sv` 模块的正确性。

## 固件文件

`firmware_muldiv.hex`（待编写）

## 伪代码

```
UART_BASE = 0x10000000

def uart_send(char): ...
def uart_send_str(str): ...
def uart_send_hex(value): ...

# === 1. MUL (有符号乘法，低 32 位) ===
a = 7
b = 6
result = a * b                 # MUL, 期望 0x0000002A (42)
uart_send_str("MUL:  ")
uart_send_hex(result)

# === 2. MULH (有符号乘法，高 32 位) ===
a = 0x7FFFFFFF    # 最大正数
b = 0x7FFFFFFF
result = (a * b) >> 32         # MULH, 期望 0x3FFFFFFF
uart_send_str("MULH: ")
uart_send_hex(result)

# === 3. DIV (有符号除法) ===
a = 100
b = 7
result = a / b                 # DIV, 期望 0x0000000E (14)
uart_send_str("DIV:  ")
uart_send_hex(result)

# === 4. DIVU (无符号除法) ===
a = 0xFFFFFFFF    # 无符号 4294967295
b = 2
result = a / b                 # DIVU, 期望 0x7FFFFFFF
uart_send_str("DIVU: ")
uart_send_hex(result)

# === 5. REM (有符号取余) ===
a = 100
b = 7
result = a % b                 # REM, 期望 0x00000002 (2)
uart_send_str("REM:  ")
uart_send_hex(result)

# === 6. REMU (无符号取余) ===
a = 0xFFFFFFFF
b = 16
result = a % b                 # REMU, 期望 0x0000000F (15)
uart_send_str("REMU: ")
uart_send_hex(result)

uart_send_str("ALL DONE\n")
while True: pass
```

## 关键点

- **M 扩展指令解码**：`rvp_decoder.sv` 中 `use_multdiv=1`，`multdiv_op` 字段选择运算类型
- **multdiv 停顿**：M 指令执行时 `multdiv_stall=1`，冻结全流水线直到 `multdiv_done=1`
- **MUL vs MULH**：MUL 取乘积低 32 位，MULH 取高 32 位（两个有符号数相乘）
- **DIV 向零截断**：RISC-V 规定除法向零截断（不是向下取整），如 -7/2 = -3（不是 -4）
- **DIVU vs DIV**：DIVU 操作数视为无符号，DIV 视为有符号
- **multdiv 模块**：`rvp_multdiv.sv` 实现多周期乘除法，每个操作需要若干周期

## 预期串口输出

```
MUL:  0000002A
MULH: 3FFFFFFF
DIV:  0000000E
DIVU: 7FFFFFFF
REM:  00000002
REMU: 0000000F
ALL DONE
```

## 预期板载现象

| 观察项 | 预期 |
|--------|------|
| LED | 无变化 |
| 数码管 | 停机后固定显示死循环地址 |
| 串口 | 输出上述 7 行结果 |

## 通过标准

- 串口输出的每个值与期望值完全一致
- 特别关注 DIV 的有符号截断和 DIVU 的无符号处理

## 失败排查

| 现象 | 可能原因 |
|------|---------|
| MUL 结果错误 | multdiv 乘法逻辑错误 |
| MULH 结果错误 | 乘法高位提取错误，或有符号/无符号处理错误 |
| DIV 结果错误 | 有符号除法实现错误（向零截断 vs 向下取整） |
| DIVU 结果错误 | 无符号除法实现错误 |
| REM 结果错误 | 取余逻辑错误 |
| 全部输出 0 | multdiv 模块未启动，`use_multdiv` 信号未正确解码 |
| 系统死机 | multdiv_stall 未正确释放，流水线永久停顿 |

## 实际测试结果

在硬件上下载固件后，串口终端输出全部 6 项乘除法运算结果，均与期望值完全一致：

```
MUL:  0000002A
MULH: 3FFFFFFF
DIV:  0000000E
DIVU: 7FFFFFFF
REM:  00000002
REMU: 0000000F
ALL DONE
```

MUL 有符号乘法（7×6=42=0x2A）、MULH 乘法高位（0x7FFFFFFF×0x7FFFFFFF 高 32 位=0x3FFFFFFF）均正确。DIV 有符号除法（100÷7=14=0x0E，向零截断）和 DIVU 无符号除法（0xFFFFFFFF÷2=0x7FFFFFFF）结果正确，REM 取余（100%7=2）和 REMU 无符号取余（0xFFFFFFFF%16=15=0x0F）也正确。multdiv 模块的多周期停顿机制工作正常，系统未死机。

| 运算 | 实际结果 | 期望值 | 是否一致 |
|------|----------|--------|----------|
| MUL  | 0000002A | 0000002A | 是 |
| MULH | 3FFFFFFF | 3FFFFFFF | 是 |
| DIV  | 0000000E | 0000000E | 是 |
| DIVU | 7FFFFFFF | 7FFFFFFF | 是 |
| REM  | 00000002 | 00000002 | 是 |
| REMU | 0000000F | 0000000F | 是 |

**测试结果：PASS**
