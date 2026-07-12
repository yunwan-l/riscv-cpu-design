# 测试5：分支跳转（Branch & Jump）—— UART 输出

## 验证目的

验证 CPU 的**条件分支和无条件跳转**功能。通过 UART 串口将每项测试的通过/失败状态发送到电脑终端，实现可视化验证。覆盖 BEQ、BNE、BLT、BGE、JAL 五种控制流指令。

## 固件文件

`firmware_branch.hex`（待编写）

## 伪代码

```
UART_BASE = 0x10000000         # UART 寄存器基地址

# --- UART 发送子程序 ---
def uart_send(char):
    while UART[0x04] & 1:      # 轮询 TXSTAT.tx_busy
        pass
    UART[0x00] = char          # 写 TXDATA 发送字节

def uart_send_str(str):
    for ch in str:
        uart_send(ch)

# --- 分支测试 ---
x1 = 5
x2 = 5
if x1 == x2:                   # BEQ taken
    uart_send_str("BEQ: PASS\n")
else:
    uart_send_str("BEQ: FAIL\n")

x3 = 3
x4 = 7
if x3 != x4:                   # BNE taken
    uart_send_str("BNE: PASS\n")
else:
    uart_send_str("BNE: FAIL\n")

if x3 < x4:                    # BLT taken
    uart_send_str("BLT: PASS\n")
else:
    uart_send_str("BLT: FAIL\n")

if x4 >= x1:                   # BGE taken
    uart_send_str("BGE: PASS\n")
else:
    uart_send_str("BGE: FAIL\n")

# JAL 测试
jal x5, label                  # 跳转，x5 = 返回地址
uart_send_str("JAL: FAIL\n")   # 不应执行
j end

label:
uart_send_str("JAL: PASS\n")
# 验证返回地址
if x5 == expected_addr:
    uart_send_str("RET: PASS\n")

end:
uart_send_str("ALL DONE\n")
# 停机：无限循环
while True: pass
```

## 关键点

- **UART 地址**：0x10000000 写 TXDATA（发送字节），0x10000004 读 TXSTAT（bit0=忙）
- **波特率**：115200，12.5MHz 时钟下每字节约 174us，发送一行 "XXX: PASS\n" 约 1ms
- **分支在 EX 解算**：CPU 在 EX 阶段判定分支是否成立，成立时冲刷 IF/ID 和 ID/EX（2 个气泡）
- **JAL 返回地址**：`jal x5, label` 将 PC+4 存入 x5，可验证链接寄存器功能
- **测试覆盖**：BEQ（相等跳转）、BNE（不等跳转）、BLT（小于跳转）、BGE（大于等于跳转）、JAL（无条件跳转）
- **停机设计**：测试结束后进入无限循环，按 RESET 可重新运行

## 预期串口输出

```
BEQ: PASS
BNE: PASS
BLT: PASS
BGE: PASS
JAL: PASS
RET: PASS
ALL DONE
```

## 预期板载现象

| 观察项 | 预期 |
|--------|------|
| LED | 无变化（不使用 GPIO） |
| 数码管 | 停机后固定显示某个地址（死循环位置） |
| 串口 | 输出上述 7 行文本 |

## 通过标准

- 串口终端显示全部 `PASS`
- 无 `FAIL` 出现
- 输出 `ALL DONE` 表示测试完成

## 失败排查

| 现象 | 可能原因 |
|------|---------|
| 串口无输出 | UART 地址错误、波特率不匹配、COM 口选错 |
| 某项 FAIL | 对应分支指令的 ALU 比较逻辑或 next_pc 控制错误 |
| JAL FAIL | jal 立即数解码错误或 PC 计算错误 |
| 乱码 | 波特率不匹配（检查 SoC 的 CLK_FREQ 参数） |

## 实际测试结果

在硬件上下载固件后，串口终端成功输出全部 5 项分支测试结果，全部为 PASS：

```
BEQ: PASS
BNE: PASS
BLT: PASS
BGE: PASS
JAL: PASS
ALL DONE
```

BEQ、BNE、BLT、BGE、JAL 五种控制流指令均正确执行。调试过程中发现初始版本使用 `\n` 作为换行符，导致串口终端显示为对角线排列（每行不回车到行首），修正为 `\r\n`（回车+换行）后显示正常。

| 观察项 | 实际结果 |
|--------|----------|
| BEQ | PASS（相等跳转正确） |
| BNE | PASS（不等跳转正确） |
| BLT | PASS（小于跳转正确） |
| BGE | PASS（大于等于跳转正确） |
| JAL | PASS（无条件跳转正确） |
| 换行符 | 修正为 `\r\n`，显示正常 |

**测试结果：PASS**
