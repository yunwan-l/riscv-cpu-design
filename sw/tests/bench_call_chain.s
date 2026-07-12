# bench_call_chain.S - 函数调用链 (无delay)
.text
.globl _start
_start:
    li   t0, 0x10010000
    li   s0, 20
chain_loop:
    nop;nop;nop;nop;nop;nop;nop;nop  # A的空间(8条)
    nop;nop;nop;nop;nop;nop;nop;nop  # B的空间(8条)
    nop;nop;nop;nop;nop;nop;nop;nop  # C的空间(8条)
    nop;nop;nop;nop;nop;nop;nop;nop  # D的空间(8条)
    addi s0, s0, -1; sw s0,0(t0)
    bnez s0, chain_loop
    li   t1, 0xFFFF; sw t1,0(t0)
spin:
    beqz x0, spin
