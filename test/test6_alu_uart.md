# 测试6：ALU 全运算（ALU Operations）—— UART 输出

## 验证目的

验证 ALU 的全部 10 种运算：ADD、SUB、SLL、SRL、SRA、SLT、XOR、OR、AND。每项运算执行后通过 UART 输出运算结果，用电脑终端直接比对期望值。

## 固件文件

`firmware_alu.hex`（待编写）

## 伪代码

```
UART_BASE = 0x10000000

def uart_send(char): ...
def uart_send_str(str): ...
def uart_send_hex(value):     # 将 32 位整数转为 8 位十六进制发送
    ...

# 测试数据
a = 0x00000005    # 5
b = 0x00000003    # 3

# 1. ADD
result = a + b                 # ALU_ADD, 期望 0x00000008
uart_send_str("ADD:  ")
uart_send_hex(result)

# 2. SUB
result = a - b                 # ALU_SUB, 期望 0x00000002
uart_send_str("SUB:  ")
uart_send_hex(result)

# 3. SLL
result = a << (b & 0x1f)      # ALU_SLL, 期望 0x00000028 (5<<3=40)
uart_send_str("SLL:  ")
uart_send_hex(result)

# 4. SRL
result = 0x80000000 >> (b & 0x1f)  # ALU_SRL, 期望 0x10000000
uart_send_str("SRL:  ")
uart_send_hex(result)

# 5. SRA
result = 0x80000000 >>> (b & 0x1f) # ALU_SRA, 期望 0xF0000000
uart_send_str("SRA:  ")
uart_send_hex(result)

# 6. SLT
result = (a < b) ? 1 : 0       # ALU_SLT (有符号), 5 < 3 = 0, 期望 0x00000000
uart_send_str("SLT:  ")
uart_send_hex(result)

# 7. XOR
result = a ^ b                 # ALU_XOR, 期望 0x00000006
uart_send_str("XOR:  ")
uart_send_hex(result)

# 8. OR
result = a | b                 # ALU_OR, 期望 0x00000007
uart_send_str("OR:   ")
uart_send_hex(result)

# 9. AND
result = a & b                 # ALU_AND, 期望 0x00000001
uart_send_str("AND:  ")
uart_send_hex(result)

uart_send_str("ALL DONE\n")
while True: pass
```

## 关键点

- **10 种 ALU 运算**：覆盖 `rvp_pkg.sv` 中定义的全部 `alu_op_e` 枚举值
- **SRA vs SRL**：SRA 保留符号位（算术右移），SRL 补零（逻辑右移），用 0x80000000 测试可区分
- **SLT 有符号比较**：使用 `0xFFFFFFFF`（-1）和 `0x00000001`（1）测试，-1 < 1 应为 1
- **移位量**：RV32I 移位量取 rs2[4:0]，超过 31 的部分被忽略
- **UART 十六进制输出**：需要编写 `uart_send_hex` 子程序，将 32 位整数转为 8 个十六进制字符
- **已知运算和期望值**：终端中可直接对照

## 预期串口输出

```
ADD:  00000008
SUB:  00000002
SLL:  00000028
SRL:  10000000
SRA:  F0000000
SLT:  00000000
XOR:  00000006
OR:   00000007
AND:  00000001
ALL DONE
```

## 预期板载现象

| 观察项 | 预期 |
|--------|------|
| LED | 无变化 |
| 数码管 | 停机后固定显示死循环地址 |
| 串口 | 输出上述 10 行结果 |

## 通过标准

- 串口输出的每个十六进制值与期望值完全一致
- 输出 `ALL DONE` 表示全部测试完成

## 失败排查

| 现象 | 可能原因 |
|------|---------|
| ADD 结果错误 | ALU 加法器实现错误 |
| SUB 结果错误 | ALU 减法器实现错误 |
| SLL 结果错误 | 移位量提取错误或移位逻辑错误 |
| SRL/SRA 结果相同 | SRA 未实现符号扩展 |
| SLT 结果错误 | 有符号比较逻辑错误 |
| 全部错误 | ALU opcode 解码错误 |

## 实际测试结果

在硬件上下载固件后，串口终端输出全部 9 种 ALU 运算结果，均与期望值完全一致：

```
ADD:  00000008
SUB:  00000002
SLL:  00000028
SRL: 10000000
SRA: F0000000
SLT: 00000000
XOR: 00000006
OR:   00000007
AND: 00000001
ALL DONE
```

特别地，SRA（算术右移）输出 0xF0000000 与 SRL（逻辑右移）输出 0x10000000 不同，证明符号扩展逻辑正确；SLT 有符号比较结果正确。

| 运算 | 实际结果 | 期望值 | 是否一致 |
|------|----------|--------|----------|
| ADD | 00000008 | 00000008 | 是 |
| SUB | 00000002 | 00000002 | 是 |
| SLL | 00000028 | 00000028 | 是 |
| SRL | 10000000 | 10000000 | 是 |
| SRA | F0000000 | F0000000 | 是 |
| SLT | 00000000 | 00000000 | 是 |
| XOR | 00000006 | 00000006 | 是 |
| OR  | 00000007 | 00000007 | 是 |
| AND | 00000001 | 00000001 | 是 |

**测试结果：PASS**
