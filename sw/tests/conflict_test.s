# conflict_test.S - 两个代码块映射到同一set, 测替换策略
#
# set 0 = addr[6:2]==0 → 地址: 0x00-0x03, 0x80-0x83, 0x100-0x103...
#
# 布局:
#   hot: 0x00-0x7C (set 0..31)
#   cold: 0x80-0xFC (set 0..31)  ← 和hot同set!
#
# hot_loop在地址0x00(set 0), cold在地址0x80(也是set 0) → 冲突!

.text
.globl _start
_start:
    li   t0, 0x10010000
    li   s0, 50               # 外层50次

hot_loop_head:
    # 这个在地址 ~0x00, set 0
    li   t1, 10               # 内层循环
1:  addi t1, t1, -1
    bnez t1, 1b

    # 跳到cold (地址应该 >0x80, 和hot_loop的某个地址同set)
    beqz x0, trampoline1

trampoline1:
    beqz x0, cold_entry

hot_continue:
    addi s0, s0, -1
    sw   s0, 0(t0)
    bnez s0, hot_ret_tramp

hot_ret_tramp:
    beqz x0, hot_loop_head

spin:
    beqz x0, spin

# ====== 用NOP填充到0x80 ======
    .balign 128               # 填充到128字节边界(0x80)

cold_entry:
    # 这个在地址0x80, 也是set 0!
    # 和hot_loop_head(0x00)冲突!
    li   t1, 5
2:  addi t1, t1, -1
    bnez t1, 2b
    beqz x0, cold_ret

cold_ret:
    beqz x0, hot_continue
