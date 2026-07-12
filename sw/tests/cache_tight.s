# cache_tight.S — 紧循环: 小代码, 应该高命中率
.text
.globl _start
_start:
    li   t0, 0x10010000      # GPIO
    li   t1, 1000             # 迭代1000次
    li   t2, 0

loop:
    addi t2, t2, 1
    sw   t2, 0(t0)            # 写LED = 循环计数 (低16位)
    addi t1, t1, -1
    bnez t1, loop

    # 结束: LED=0xFFFF
    li   t2, 0xFFFF
    sw   t2, 0(t0)
spin:
    beqz x0, spin
