# cache_big.S — 超256B的程序, 测容量+冲突缺失
# 8个代码块, 每个~48B, 总~384B > 缓存256B
.text
.globl _start
_start:
    li   t0, 0x10010000
    li   t5, 20               # 外层20次

outer:
    # 块1: delay + LED
    li   t1, 100
1:  addi t1,t1,-1; bnez t1,1b
    li   t1,0x0001; sw t1,0(t0)
    nop;nop;nop;nop;nop;nop;nop;nop

    # 块2
    li   t1, 100
2:  addi t1,t1,-1; bnez t1,2b
    li   t1,0x0002; sw t1,0(t0)
    nop;nop;nop;nop;nop;nop;nop;nop

    # 块3
    li   t1, 100
3:  addi t1,t1,-1; bnez t1,3b
    li   t1,0x0004; sw t1,0(t0)
    nop;nop;nop;nop;nop;nop;nop;nop

    # 块4
    li   t1, 100
4:  addi t1,t1,-1; bnez t1,4b
    li   t1,0x0008; sw t1,0(t0)
    nop;nop;nop;nop;nop;nop;nop;nop

    # 块5
    li   t1, 100
5:  addi t1,t1,-1; bnez t1,5b
    li   t1,0x0010; sw t1,0(t0)
    nop;nop;nop;nop;nop;nop;nop;nop

    # 块6
    li   t1, 100
6:  addi t1,t1,-1; bnez t1,6b
    li   t1,0x0020; sw t1,0(t0)
    nop;nop;nop;nop;nop;nop;nop;nop

    # 块7
    li   t1, 100
7:  addi t1,t1,-1; bnez t1,7b
    li   t1,0x0040; sw t1,0(t0)
    nop;nop;nop;nop;nop;nop;nop;nop

    # 块8
    li   t1, 100
8:  addi t1,t1,-1; bnez t1,8b
    li   t1,0x0080; sw t1,0(t0)
    nop;nop;nop;nop;nop;nop;nop;nop

    addi t5,t5,-1
    sw   t5,0(t0)
    bnez t5, outer

    li   t1,0xFFFF; sw t1,0(t0)
spin:
    beqz x0, spin
