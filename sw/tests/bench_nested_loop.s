# bench_nested_loop.S - 嵌套循环 (无delay, 纯取指)
.text
.globl _start
_start:
    li   t0, 0x10010000
    li   s0, 30               # 外层30次
outer:
    li   s1, 15               # 内层15次
inner:
    addi s1, s1, -1
    sw   s1, 0(t0)
    bnez s1, inner            # 内层短反向循环
    addi s0, s0, -1
    sw   s0, 0(t0)
    bnez s0, outer
    li   t1, 0xFFFF; sw t1,0(t0)
spin:
    beqz x0, spin
