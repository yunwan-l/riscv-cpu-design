# bench_branchy.S - 分支密集 (无delay)
.text
.globl _start
_start:
    li   t0, 0x10010000
    li   s0, 30
branch_loop:
    andi t1, s0, 3
    beqz t1, path0
    li   t2, 1
    beq  t1, t2, path1
    li   t2, 2
    beq  t1, t2, path2
    nop;nop;nop;nop;nop;nop;nop;nop  # path3 body
    beqz x0, path_done
path0:
    nop;nop;nop;nop;nop;nop;nop;nop
    beqz x0, path_done
path1:
    nop;nop;nop;nop;nop;nop;nop;nop
    beqz x0, path_done
path2:
    nop;nop;nop;nop;nop;nop;nop;nop
path_done:
    addi s0, s0, -1; sw s0,0(t0)
    bnez s0, branch_loop
    li   t1, 0xFFFF; sw t1,0(t0)
spin:
    beqz x0, spin
