# cache_wide.S — 大代码: 超过256B, 测容量缺失
# 串联多个紧循环 + NOP填充, 总大小 ~400B
.text
.globl _start
_start:
    li   t0, 0x10010000
    li   t5, 10               # 外层循环10次

outer_loop:
    # === 代码块1: ~60B ===
    li   t1, 200
1:  addi t1, t1, -1
    bnez t1, 1b
    nop; nop; nop; nop; nop
    nop; nop; nop; nop; nop

    # === 代码块2: ~60B (不同地址, 可能踢掉块1) ===
    li   t1, 200
2:  addi t1, t1, -1
    bnez t1, 2b
    nop; nop; nop; nop; nop
    nop; nop; nop; nop; nop

    # === 代码块3: ~60B ===
    li   t1, 200
3:  addi t1, t1, -1
    bnez t1, 3b
    nop; nop; nop; nop; nop
    nop; nop; nop; nop; nop

    # === 代码块4: ~60B ===
    li   t1, 200
4:  addi t1, t1, -1
    bnez t1, 4b
    nop; nop; nop; nop; nop
    nop; nop; nop; nop; nop

    addi t5, t5, -1
    sw   t5, 0(t0)
    bnez t5, outer_loop

    li   t1, 0xFFFF
    sw   t1, 0(t0)
spin:
    beqz x0, spin
