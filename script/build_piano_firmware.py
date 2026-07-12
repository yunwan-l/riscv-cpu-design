#!/usr/bin/env python3
"""
build_piano_firmware.py - 编译 RVP 钢琴固件

使用项目的 rv_assembler 将 RISC-V 汇编编译为 hex 文件。
固件功能：读取 16 个拨码开关，映射为音符，通过 UART 发送给 PC。

用法: python build_piano_firmware.py
输出: firmware_piano.hex (项目根目录)
"""

import sys
import os

# 添加 sw/tests 到路径，导入项目自带汇编器
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))
SW_TESTS_DIR = os.path.join(PROJECT_ROOT, 'sw', 'tests')

sys.path.insert(0, SW_TESTS_DIR)
from rv_assembler import Assembler

# ============================================================================
# 钢琴固件汇编代码
# ============================================================================
# 设计说明：
#   - CPU 无延迟槽（分支/跳转时流水线 flush），无需手动插 NOP
#   - 寄存器分配：s0=GPIO基址, s1=UART基址, s2=Piano基址, s3=上次开关值
#   - 协议：开关变化时发送 1 字节（0=静音, 1-16=音符索引）
#
# 地址映射：
#   0x10000000 UART  (TXDATA=0x00, TXSTAT=0x04 bit0=tx_busy)
#   0x10010000 GPIO  (OUTPUT=0x00, INPUT=0x04)
#   0x10040000 Piano (NOTE=0x00, FREQ=0x04)
# ============================================================================

piano_asm = """
# === 初始化 ===
lui s0, 0x10010       # s0 = GPIO 基址 0x10010000
lui s1, 0x10000       # s1 = UART 基址 0x10000000
lui s2, 0x10040       # s2 = Piano基址 0x10040000
sw x0, 0(s0)          # LED 全灭
li s3, 0              # last_switch = 0

# === 主循环 ===
main_loop:
  lw t0, 4(s0)        # t0 = GPIO_INPUT（读取 16 个开关）
  beq t0, s3, do_delay # 开关未变化，跳到延时

  # --- 开关变化，计算新音符 ---
  mv s3, t0            # 更新 last_switch

  # 优先编码器：找最低位为 1 的开关位置
  li t1, 0             # note = 0（静音）
  li t2, 16            # 剩余检测位数

pe_loop:
  beqz t2, pe_done     # 16 位都检测完，note 保持 0
  andi t3, t0, 1       # 测试最低位
  bnez t3, pe_found    # 找到按键
  srli t0, t0, 1       # 右移
  addi t2, t2, -1      # 计数器减一
  j pe_loop

pe_found:
  # t2 = 剩余位数 = 16 - 位置
  # note = 17 - t2
  li t1, 17
  sub t1, t1, t2

pe_done:
  # t1 = 音符索引 (0=静音, 1-16)

  # 写入钢琴外设（硬件查表）
  sw t1, 0(s2)

  # 写入 GPIO 输出（LED 反馈）
  sw t1, 0(s0)

  # --- 通过 UART 发送音符字节 ---
uart_wait:
  lw t3, 4(s1)         # 读 TXSTAT
  andi t3, t3, 1       # bit0 = tx_busy
  bnez t3, uart_wait   # 忙则等待
  sb t1, 0(s1)         # 写 TXDATA，发送音符字节

# === 延时循环（约 0.2ms 消抖） ===
do_delay:
  li t0, 2000
delay_loop:
  addi t0, t0, -1
  bnez t0, delay_loop
  j main_loop
"""

# ============================================================================
# 编译
# ============================================================================
def main():
    print("[BUILD] 正在编译钢琴固件...")

    asm = Assembler()
    lines = [l for l in piano_asm.strip().split('\n')]
    hex_words = asm.assemble(lines)

    # 输出路径
    output_path = os.path.join(PROJECT_ROOT, 'firmware_piano.hex')
    with open(output_path, 'w') as f:
        for h in hex_words:
            f.write(h + '\n')

    print(f"[OK] 固件编译成功: {output_path}")
    print(f"     指令数: {len(hex_words)}")
    print(f"     文件大小: {os.path.getsize(output_path)} bytes")

    # 打印前几条指令用于调试
    print("\n[BUILD] 前 10 条指令:")
    for i, h in enumerate(hex_words[:10]):
        print(f"     0x{i*4:04X}: {h}")

    return output_path

if __name__ == '__main__':
    main()
