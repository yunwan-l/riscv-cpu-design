# conflict3.S — 3个块映射到同一set, 测试替换策略
# set 0 = addr[6:2]==0 → 0x00, 0x80, 0x100, 0x180...
# 块A(0x00): 热循环, 应被保护
# 块B(0x80): 温, 偶尔访问
# 块C(0x100): 冷, 很少访问
# 只有2路 → 替换策略必须选踢谁

.text
.globl _start
_start:
    li   t0, 0x10010000
    li   s0, 30               # 外层30轮

outer_loop:
    # === 热循环 A (地址0x00附近, set 0) ===
    li   t1, 10
1:  addi t1, t1, -1
    bnez t1, 1b
    sw   s0, 0(t0)            # LED = 外层计数

    # === 跳转到冷块C (地址0x100附近) ===
    beqz x0, goto_C
ret_from_C:

    # === 跳转到温块B (地址0x80附近) ===
    beqz x0, goto_B
ret_from_B:

    addi s0, s0, -1
    bnez s0, outer_loop

    li   t1, 0xFFFF; sw t1,0(t0)
spin:
    beqz x0, spin

# ===== 填充NOP把B推到0x80 (set 0) =====
    nop;nop;nop;nop;nop;nop;nop;nop
    nop;nop;nop;nop;nop;nop;nop;nop
    nop;nop;nop;nop;nop;nop;nop;nop
    nop;nop;nop;nop
    .balign 128
goto_B:
    # 块B在0x80 (set 0)
    li   t1, 5
2:  addi t1, t1, -1
    bnez t1, 2b
    beqz x0, ret_from_B

# ===== 填充NOP把C推到0x100 (set 0) =====
    nop;nop;nop;nop;nop;nop;nop;nop
    nop;nop;nop;nop;nop;nop;nop;nop
    nop;nop;nop;nop;nop;nop;nop;nop
    nop;nop;nop;nop;nop;nop;nop;nop
    nop;nop;nop;nop;nop;nop;nop;nop
    nop;nop;nop;nop;nop;nop;nop;nop
    .balign 256
goto_C:
    # 块C在0x100 (set 0)
    li   t1, 5
3:  addi t1, t1, -1
    bnez t1, 3b
    beqz x0, ret_from_C
