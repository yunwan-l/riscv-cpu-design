#!/usr/bin/env python3
"""
gen_overflow_test.py — 超容量测试程序生成器
============================================
生成工作集远超 cache 容量 (2KB=512条指令) 的测试程序，
用于在 Nexys4 DDR 板上测试 PMRU8 I-Cache 的替换策略。

设计要点:
  - 工作集: 1320条指令 (2.58× cache容量)
  - 20个代码块 × 6单元 × 11条/单元 = 1320条
  - 每单元: 2个迷你循环(5条) + 1个SEQ复位分支(1条)
  - 热块(偶数): 内层循环10次 → 高hit_count, PMRU保护
  - 冷块(奇数): 内层循环2次 → 低hit_count, 应被驱逐
  - 外层循环10次 → 总访问 ~61K次 (8K-80K范围内)
  - 每≤12条指令有分支 → 避免流式旁路(阈值16)

PMRU优势: 保护热块(高hit_count), 驱逐冷块
LRU劣势: 按时间顺序驱逐, 可能踢掉热块
"""

import sys
import os

# 导入公共汇编器
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
from gen_board_test import *


def gen_test_overflow():
    """
    超容量测试：工作集 1320条 > cache容量 512条 (2.58×)

    结构:
      setup → 外层循环10次 → [20块×6单元×(2迷你循环+SEQ复位)] → 读结果 → 报告

    每个迷你循环 (5条指令):
      li A3, count        # 加载循环计数
      loop:
        addi A3, A3, -1   # 计数递减
        addi A4, A4, 1    # 累加器
        andi/ori A4, ...  # 位操作
      bne A3, x0, loop    # 循环

    SEQ复位 (1条指令):
      beq x0, x0, +4      # 无条件跳转到下一条指令, 复位SEQ计数器
    """
    prog = Program()

    # === 初始化 (5条: 3 lui + 2 lw) ===
    gen_setup(prog)

    # === 外层循环计数 ===
    prog.emit(addi(A2, ZERO, 10))      # li A2, 10 (外层10次)
    prog.label('overflow_outer')

    # === 20个代码块 ===
    NUM_BLOCKS = 20
    UNITS_PER_BLOCK = 6

    for block in range(NUM_BLOCKS):
        is_hot = (block % 2 == 0)
        loop_count = 10 if is_hot else 2

        for unit in range(UNITS_PER_BLOCK):
            # --- 迷你循环 A (5条) ---
            prog.emit(addi(A3, ZERO, loop_count))    # li A3, count
            prog.label(f'b{block}u{unit}a')
            prog.emit(addi(A3, A3, -1))               # body 1
            prog.emit(addi(A4, A4, 1))                # body 2
            prog.emit(andi(A4, A4, 0xFF))             # body 3
            prog.emit_branch(A3, ZERO, f'b{block}u{unit}a', bne)

            # --- 迷你循环 B (5条) ---
            prog.emit(addi(A3, ZERO, loop_count))    # li A3, count
            prog.label(f'b{block}u{unit}b')
            prog.emit(addi(A3, A3, -1))               # body 1
            prog.emit(addi(A4, A4, 1))                # body 2
            prog.emit(ori(A4, A4, 0x55))              # body 3
            prog.emit_branch(A3, ZERO, f'b{block}u{unit}b', bne)

            # --- SEQ复位分支 (1条, 最后一单元省略) ---
            is_last = (block == NUM_BLOCKS - 1 and unit == UNITS_PER_BLOCK - 1)
            if not is_last:
                # beq x0, x0, +4: 无条件跳转到下一条指令
                # pc_delta = (pc+4) - (pc+8) = -4 ≠ 4 → SEQ计数器复位
                prog.emit(beq(ZERO, ZERO, 4))

    # === 外层循环递减 ===
    prog.emit(addi(A2, A2, -1))
    # B-type bne offset to overflow_outer (-5280B) exceeds 13-bit signed
    # immediate range (-4096~+4094). Use beq+JAL pattern instead:
    #   beq skips JAL when loop is done; JAL has ±1MB range
    prog.emit_branch(A2, ZERO, 'overflow_done', beq)
    prog.emit_jal(ZERO, 'overflow_outer')
    prog.label('overflow_done')

    # === 读取最终计数器 ===
    gen_read_final(prog)

    # 跳过函数定义
    prog.emit_jal(ZERO, 'do_report')

    # === UART 函数定义 ===
    gen_uart_send_byte(prog)
    gen_send_u32(prog)
    gen_send_decimal(prog)

    # === 报告代码 ===
    prog.label('do_report')
    gen_report_and_halt(prog, test_marker=0x4F)  # 'O' = Overflow

    return prog.assemble()


def main():
    print('超容量测试程序生成器 (Overflow Test)')
    print('=' * 60)
    print(f'Cache容量: 2KB = 512条指令 (8路 × 64组 × 4B)')
    print(f'测试工作集: 1320条指令 (2.58× cache容量)')
    print(f'结构: 20块 × 6单元 × 11条 = 1320条')
    print(f'热块(偶数): 内层循环10次 | 冷块(奇数): 内层循环2次')
    print(f'外层循环: 10次 → 总访问 ~61K次')
    print(f'SEQ安全: 最大连续SEQ = 12 < 16 (无流式旁路)')
    print()

    instrs = gen_test_overflow()
    total_bytes = len(instrs) * 4

    print(f'生成结果: {len(instrs)} 条指令 = {total_bytes} 字节')
    if len(instrs) > 2048:
        print(f'警告: 超过2048字(8KB) BRAM限制! 当前: {len(instrs)}字')
    else:
        print(f'BRAM占用: {len(instrs)}/2048 字 ({len(instrs)*100//2048}%)')

    # 写入 hex 文件
    hex_path = os.path.join(SCRIPT_DIR, 'test_overflow.hex')
    with open(hex_path, 'w') as f:
        for instr in instrs:
            f.write(f'{instr & 0xFFFFFFFF:08X}\n')
    print(f'\n已生成: {hex_path}')

    # 同时写入 firmware.hex (供 Vivado 直接使用)
    fw_path = os.path.join(SCRIPT_DIR, '..', 'synth', 'vivado', 'firmware.hex')
    with open(fw_path, 'w') as f:
        for instr in instrs:
            f.write(f'{instr & 0xFFFFFFFF:08X}\n')
    print(f'已复制: {os.path.abspath(fw_path)}')

    print('\n' + '=' * 60)
    print('下一步: 运行 Vivado 综合生成 bit 文件')
    print('  vivado -mode batch -source synth/vivado/run_full.tcl')


if __name__ == '__main__':
    main()
