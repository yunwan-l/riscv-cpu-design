#!/usr/bin/env python3
"""
gen_thrash_big.py — 十万级缓存颠簸测试程序生成器
==================================================
设计目标：
  - 总访问量 > 100,000 次
  - Phase 1: 冲突缺失 — 16块映射同一set，500轮 → ~80K访问
  - Phase 2: 容量缺失 — 40轮×512条顺序 → ~20K访问
  - 指令量 < 2048 (BRAM限制)

指令布局：
  setup(5) + li(1) + Phase1(16×64=1024) + Phase2(512+3) + report/uart(~60) ≈ 1607条
  增加外层循环次数不改指令量，只改 li 的立即数

访问量估算（5级流水，每 taken branch 产生2个 wrong-path fetch）：
  Phase 1: 500轮 × 16块 × (1 NOP + 1 JAL + 2 wrong-path) = 500×16×4 = 32,000
  Phase 2: 40轮 × 512条 × (1执行 + 偶尔wrong-path) ≈ 20,500
  setup + report ≈ 50
  总计 ≈ ~52,550... 不够10万

需要增加：Phase 1 设为 1000轮，Phase 2 设为 100轮
  Phase 1: 1000×16×4 = 64,000
  Phase 2: 100×512×~2 = 102,400 → 太多Phase2了

平衡：Phase 1=800轮, Phase 2=40轮
  Phase 1: 800×16×4 = 51,200
  Phase 2: 40×205 = 8,200 (每轮512 NOP=顺序访问512次，但只有最后1条bne产生wrong-path)
  实际Phase 2每轮: 512次顺序 + 2 wrong-path = 514
  Phase 2: 40×514 = 20,560
  总计 ≈ 71,760 → 还是不够

再增加: Phase 1=1000轮, Phase 2=50轮
  Phase 1: 1000×16×4 = 64,000
  Phase 2: 50×514 = 25,700
  总计 ≈ 89,750 → 接近

Phase 1=1200轮, Phase 2=50轮
  Phase 1: 1200×16×4 = 76,800
  Phase 2: 50×514 = 25,700
  总计 ≈ 102,550 → 达标！
"""

import sys
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
from gen_board_test import *


def gen_thrash_big():
    """十万级缓存颠簸测试。
    
    Phase 1: 1200轮冲突缺失（16块争8路）
    Phase 2: 50轮容量缺失（512条顺序NOP）
    总访问量 ~100K+
    """
    prog = Program()

    # === 初始化 ===
    gen_setup(prog)

    # === Phase 1: 冲突缺失 × 1200轮 ===
    prog.emit_list(li(A2, 1200))
    prog.label('thrash_loop')

    for i in range(15):
        prog.label(f'blk{i}')
        prog.emit(nop())                 # 有用指令
        prog.emit_jal(ZERO, f'blk{i+1}') # 跳到下一块
        prog.pad_nop(62)                 # 填充到64条间隔

    # 第16块：beq+JAL 模式（避免B-type溢出）
    prog.label('blk15')
    prog.emit(nop())
    prog.emit(addi(A2, A2, -1))
    prog.emit_branch(A2, ZERO, 'phase2_start', beq)  # 循环结束→Phase2
    prog.emit_jal(ZERO, 'thrash_loop')                 # 否则继续循环

    # === Phase 2: 容量缺失 × 50轮 ===
    prog.label('phase2_start')
    prog.emit_list(li(A3, 50))
    prog.label('phase2_loop')
    prog.pad_nop(512)                    # 512条顺序NOP = 1×cache容量
    prog.emit(addi(A3, A3, -1))
    prog.emit_branch(A3, ZERO, 'phase2_done', beq)
    prog.emit_jal(ZERO, 'phase2_loop')

    # === 读取最终计数器 ===
    prog.label('phase2_done')
    gen_read_final(prog)

    # 跳过函数定义
    prog.emit_jal(ZERO, 'do_report')

    # === UART 函数定义 ===
    gen_uart_send_byte(prog)
    gen_send_u32(prog)
    gen_send_decimal(prog)

    # === 报告代码 ===
    prog.label('do_report')
    gen_report_and_halt(prog, test_marker=0x54)  # 'T' = Thrash

    return prog.assemble()


def main():
    print('十万级缓存颠簸测试程序生成器 (Thrash Big)')
    print('=' * 60)

    instrs = gen_thrash_big()
    total_bytes = len(instrs) * 4

    print(f'Cache容量: 2KB = 512条指令 (8路 × 64组 × 4B)')
    print(f'测试指令量: {len(instrs)}条 = {total_bytes}字节')
    if len(instrs) > 2048:
        print(f'错误: 超过2048字(8KB) BRAM限制! 当前: {len(instrs)}字')
        sys.exit(1)
    print(f'BRAM占用: {len(instrs)}/2048 字 ({len(instrs)*100//2048}%)')
    print()

    # 估算访问量
    # Phase 1: 1200轮 × 16块 × (1 NOP + 1 JAL + 2 wrong-path) = 1200×16×4 = 76,800
    # Phase 2: 50轮 × (512 NOP + 1 addi + 1 beq/jal + 2 wrong-path) ≈ 50×516 = 25,800
    # setup + report ≈ 50
    est = 1200*16*4 + 50*516 + 50
    print(f'预计访问量: ~{est}次')
    print(f'Phase 1: 1200轮冲突缺失 (~76,800次)')
    print(f'Phase 2: 50轮容量缺失 (~25,800次)')
    print()

    # 写入 hex 文件
    hex_path = os.path.join(SCRIPT_DIR, 'test_thrash_big.hex')
    with open(hex_path, 'w') as f:
        for instr in instrs:
            f.write(f'{instr & 0xFFFFFFFF:08X}\n')
    print(f'已生成: {hex_path}')

    # 同时写入 firmware.hex (3个位置)
    for fw_path in [
        os.path.join(SCRIPT_DIR, '..', 'synth', 'vivado', 'firmware.hex'),
        os.path.join(SCRIPT_DIR, '..', 'rtl', 'core', 'firmware.hex'),
    ]:
        with open(fw_path, 'w') as f:
            for instr in instrs:
                f.write(f'{instr & 0xFFFFFFFF:08X}\n')
        print(f'已复制: {os.path.abspath(fw_path)}')

    print('\n' + '=' * 60)


if __name__ == '__main__':
    main()
