# 测试7：存储器读写（Memory R/W）—— UART 输出

## 验证目的

验证数据存储器的**字节/半字/字读写**功能，包括符号扩展和无符号读取。通过 UART 输出每次读回的值，验证存储器接口的正确性。

## 固件文件

`firmware_mem.hex`（待编写）

## 伪代码

```
RAM_BASE = 0x00000000           # 数据存储器基地址
UART_BASE = 0x10000000

def uart_send(char): ...
def uart_send_str(str): ...
def uart_send_hex(value): ...

# === 1. 字读写 (SW/LW) ===
RAM[0] = 0x00000041            # sw
val = RAM[0]                   # lw
uart_send_str("LW:  ")
uart_send_hex(val)             # 期望 0x00000041

# === 2. 字节写、符号扩展读 (SB/LB) ===
RAM[4] = 0x41                  # sb (写低字节)
val = RAM[4]                   # lb (符号扩展)
uart_send_str("LB:  ")
uart_send_hex(val)             # 期望 0x00000041

# === 3. 字节写、无符号读 (SB/LBU) ===
RAM[8] = 0x80                  # sb (写 0x80)
val = RAM[8]                   # lbu (无符号)
uart_send_str("LBU: ")
uart_send_hex(val)             # 期望 0x00000080

# === 4. 半字写、符号扩展读 (SH/LH) ===
RAM[12] = 0x0041               # sh (写低 16 位)
val = RAM[12]                  # lh (符号扩展)
uart_send_str("LH:  ")
uart_send_hex(val)             # 期望 0x00000041

# === 5. 负数符号扩展 (SB → LB) ===
RAM[16] = 0xFF                 # sb (写 0xFF)
val = RAM[16]                  # lb (符号扩展: 0xFF → 0xFFFFFFFF)
uart_send_str("LBn: ")
uart_send_hex(val)             # 期望 0xFFFFFFFF

# === 6. 负数半字符号扩展 (SH → LH) ===
RAM[20] = 0x8000               # sh (写 0x8000)
val = RAM[20]                  # lh (符号扩展: 0x8000 → 0xFFFF8000)
uart_send_str("LHn: ")
uart_send_hex(val)             # 期望 0xFFFF8000

uart_send_str("ALL DONE\n")
while True: pass
```

## 关键点

- **存储器地址**：Data RAM 映射在 0x00000000，`rvp_data_mem.sv` 支持 B/H/W 访问
- **符号扩展**：LB 将 byte[7] 符号扩展到 32 位，LBU 补零；LH 将 half[15] 符号扩展
- **写入掩码**：SB 只写最低字节，SH 只写低 16 位，SW 写 32 位，验证 `rvp_data_mem.sv` 的 byte-enable 逻辑
- **地址对齐**：所有访问使用 4 字节对齐地址（0, 4, 8, 12, 16, 20）
- **SoC 地址译码**：`dbus_addr[31:16] == 16'h0000` 命中 Data RAM

## 预期串口输出

```
LW:  00000041
LB:  00000041
LBU: 00000080
LH:  00000041
LBn: FFFFFFFF
LHn: FFFF8000
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
- 特别关注 `LBn` 和 `LHn` 的符号扩展是否正确

## 失败排查

| 现象 | 可能原因 |
|------|---------|
| LW 值错误 | 存储器写入或读取逻辑错误 |
| LB 符号扩展错误 | `rvp_data_mem.sv` 中 LB 符号扩展逻辑缺失 |
| LBU 输出 0xFFFFFFFF | LBU 未做无符号处理（误用了 LB 逻辑） |
| SH 写入错误 | 半字写入掩码错误，写入了全部 32 位 |
| LHn 输出 00008000 | LH 未做符号扩展 |

## 实际测试结果

在硬件上下载固件后，串口终端输出全部 6 项存储器读写测试结果，均与期望值完全一致：

```
LW:  00000041
LB:  00000041
LBU: 00000080
LH:  00000041
LBn: FFFFFFFF
LHn: FFFF8000
ALL DONE
```

字读写（LW）、字节读写（LB/LBU）、半字读写（LH）均正确。特别验证了符号扩展逻辑：LB 读取 0xFF 正确符号扩展为 0xFFFFFFFF，LH 读取 0x8000 正确符号扩展为 0xFFFF8000；LBU 无符号读取 0x80 输出 0x00000080，未做符号扩展。

| 测试项 | 实际结果 | 期望值 | 是否一致 |
|--------|----------|--------|----------|
| LW  | 00000041 | 00000041 | 是 |
| LB  | 00000041 | 00000041 | 是 |
| LBU | 00000080 | 00000080 | 是 |
| LH  | 00000041 | 00000041 | 是 |
| LBn | FFFFFFFF | FFFFFFFF | 是 |
| LHn | FFFF8000 | FFFF8000 | 是 |

**测试结果：PASS**
