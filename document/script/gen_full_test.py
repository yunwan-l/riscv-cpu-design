#!/usr/bin/env python3
"""Generate full_test.hex - Simplified version without problematic comments."""

import sys, os
sys.path.insert(0, r"E:\rvp_nexys\sw\tests")
from rv_assembler import Assembler

SRC = r"""
_start:
    lui t0, 0x10010
    lui t6, 0x10000
    lui t3, 0x10020
    addi s2, x0, 1

marquee:
    sw s2, 0(t0)
    addi a0, x0, 80
delay_m:
    addi a0, a0, -1
    bnez a0, delay_m
    slli s2, s2, 1
    andi s2, s2, 0xFFFF
    bnez s2, marquee
    addi s2, x0, 1

    addi s2, x0, 0x8000
marquee_r:
    sw s2, 0(t0)
    addi a0, x0, 80
delay_r:
    addi a0, a0, -1
    bnez a0, delay_r
    srli s2, s2, 1
    bnez s2, marquee_r
    addi s2, x0, 0x8000

    lui a5, 0x10000
    addi a4, x0, 0x48
    sb a4, 0(a5)
    addi a0, x0, 30
delay_h:
    addi a0, a0, -1
    bnez a0, delay_h

    addi a4, x0, 0x65
    sb a4, 0(a5)
    addi a0, x0, 30
delay_e:
    addi a0, a0, -1
    bnez a0, delay_e

    addi a4, x0, 0x6C
    sb a4, 0(a5)
    addi a0, x0, 30
delay_l1:
    addi a0, a0, -1
    bnez a0, delay_l1

    addi a4, x0, 0x6C
    sb a4, 0(a5)
    addi a0, x0, 30
delay_l2:
    addi a0, a0, -1
    bnez a0, delay_l2

    addi a4, x0, 0x6F
    sb a4, 0(a5)
    addi a0, x0, 30
delay_o:
    addi a0, a0, -1
    bnez a0, delay_o

    addi a4, x0, 0x20
    sb a4, 0(a5)
    addi a0, x0, 30
delay_sp:
    addi a0, a0, -1
    bnez a0, delay_sp

    addi a4, x0, 0x52
    sb a4, 0(a5)
    addi a0, x0, 30
delay_r1:
    addi a0, a0, -1
    bnez a0, delay_r1

    addi a4, x0, 0x56
    sb a4, 0(a5)
    addi a0, x0, 30
delay_v:
    addi a0, a0, -1
    bnez a0, delay_v

    addi a4, x0, 0x50
    sb a4, 0(a5)
    addi a0, x0, 30
delay_p:
    addi a0, a0, -1
    bnez a0, delay_p

    addi a4, x0, 0x21
    sb a4, 0(a5)
    addi a0, x0, 30
delay_ex:
    addi a0, a0, -1
    bnez a0, delay_ex

    addi a4, x0, 0x0D
    sb a4, 0(a5)
    addi a0, x0, 30
delay_cr:
    addi a0, a0, -1
    bnez a0, delay_cr

    addi a4, x0, 0x0A
    sb a4, 0(a5)
    addi a0, x0, 30
delay_lf:
    addi a0, a0, -1
    bnez a0, delay_lf

    addi a4, x0, 1
    sw a4, 4(t3)
    nop
    nop
    nop
    nop
    addi a0, x0, 20
delay_tmr:
    addi a0, a0, -1
    bnez a0, delay_tmr

    lw a4, 0(t3)
    sw a4, 0(t0)
    addi a0, x0, 10
delay_disp:
    addi a0, a0, -1
    bnez a0, delay_disp

    lw a4, 4(t0)
    sw a4, 0(t0)
    addi a0, x0, 20
delay_sw:
    addi a0, a0, -1
    bnez a0, delay_sw

    addi s2, x0, 1
main_loop:
    sw s2, 0(t0)
    lw a4, 4(t0)
    andi a5, a4, 1
    beqz a5, shift_left
    srli s2, s2, 1
    j shift_done
shift_left:
    slli s2, s2, 1
shift_done:
    andi s2, s2, 0xFFFF
    beqz s2, reset_pat
    addi a0, x0, 40
    j delay_loop
reset_pat:
    addi s2, x0, 1
delay_loop:
    addi a0, a0, -1
    bnez a0, delay_loop
    j main_loop
"""

asm = Assembler()
lines = [l for l in SRC.strip().split('\n')]
hex_words = asm.assemble(lines)

TARGET = r"E:\rvp_nexys\sw\tests\full_test_words.hex"
with open(TARGET, 'w') as f:
    for w in hex_words:
        f.write(w + '\n')

print(f"OK: {len(hex_words)} instructions -> {TARGET}")
# Print first few and check values
from rv_assembler import REG_NAMES
for i, w in enumerate(hex_words[:10]):
    print(f"  [{i}] 0x{w}")
