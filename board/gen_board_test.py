#!/usr/bin/env python3
"""
gen_board_test.py — 板载 I-Cache 测试程序生成器
================================================
生成 RISC-V 机器码 hex 文件，用于在 Nexys4 板上测试 PMRU8 I-Cache。

每个测试程序的结构：
  1. 读取初始 hit_count / miss_count（从 MMIO 性能计数器）
  2. 执行特定访问模式的测试代码
  3. 读取最终 hit_count / miss_count
  4. 计算 delta 并求命中率
  5. 将命中率写入 GPIO（LED 显示，0-1000 对应 0.0%-100.0%）
  6. 通过 UART 发送结果（二进制格式：标记 + 4字节hit_delta + 4字节miss_delta）
  7. 死循环（halt）

生成 4 个测试 hex 文件：
  test_loop.hex     — 紧凑循环（4指令循环体，10000次迭代）
  test_sequential.hex — 顺序执行（512条NOP，约2KB，与cache等大）
  test_branchy.hex   — 分支密集（交替跳转到远地址）
  test_mixed.hex     — 混合模式（顺序+循环+分支）

使用方法：
  python gen_board_test.py
  → 在当前目录生成 4 个 .hex 文件
  → 复制需要的文件到 synth/vivado/firmware.hex 进行综合
"""

import struct
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# ============================================================================
# Mini RISC-V 汇编器（RV32IM，仅生成所需指令）
# ============================================================================

# 寄存器名
ZERO=0;  RA=1;  SP=2;  GP=3;  TP=4
T0=5;   T1=6;  T2=7
S0=8;   S1=9;  S2=18
A0=10;  A1=11; A2=12; A3=13; A4=14; A5=15; A6=16; A7=17

# MMIO 地址
UART_BASE   = 0x10000000
GPIO_BASE   = 0x10010000
PERF_BASE   = 0x10030000
PERF_HIT    = 0x14   # offset from PERF_BASE
PERF_MISS   = 0x18

# ---------------------------------------------------------------------------
# 指令编码函数
# ---------------------------------------------------------------------------

def lui(rd, imm20):
    """LUI rd, imm20 — Load Upper Immediate (imm20 是高20位)"""
    imm20 &= 0xFFFFF
    return (imm20 << 12) | (rd << 7) | 0x37

def auipc(rd, imm20):
    """AUIPC rd, imm20"""
    imm20 &= 0xFFFFF
    return (imm20 << 12) | (rd << 7) | 0x17

def jal(rd, offset):
    """JAL rd, offset — Jump and Link (offset 为字节偏移，必须是偶数)"""
    offset &= 0x1FFFFF  # 21-bit signed
    # 处理负数
    if offset & 0x100000:
        offset = offset - 0x200000
    offset &= 0x1FFFFF
    imm20 = (offset >> 20) & 0x1
    imm10_1 = (offset >> 1) & 0x3FF
    imm11 = (offset >> 11) & 0x1
    imm19_12 = (offset >> 12) & 0xFF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | 0x6F

def jalr(rd, rs1, offset=0):
    """JALR rd, rs1, offset"""
    return ((offset & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x67

def beq(rs1, rs2, offset):
    """BEQ rs1, rs2, offset"""
    return _branch(rs1, rs2, offset, 0)

def bne(rs1, rs2, offset):
    """BNE rs1, rs2, offset"""
    return _branch(rs1, rs2, offset, 1)

def blt(rs1, rs2, offset):
    return _branch(rs1, rs2, offset, 4)

def bge(rs1, rs2, offset):
    return _branch(rs1, rs2, offset, 5)

def _branch(rs1, rs2, offset, funct3):
    offset &= 0x1FFF  # 13-bit signed
    if offset & 0x1000:
        offset = offset - 0x2000
    offset &= 0x1FFF
    imm12 = (offset >> 12) & 0x1
    imm10_5 = (offset >> 5) & 0x3F
    imm4_1 = (offset >> 1) & 0xF
    imm11 = (offset >> 11) & 0x1
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_1 << 8) | (imm11 << 7) | 0x63

def lw(rd, rs1, offset):
    """LW rd, offset(rs1)"""
    return ((offset & 0xFFF) << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | 0x03

def sw(rs2, rs1, offset):
    """SW rs2, offset(rs1)"""
    imm11_5 = (offset >> 5) & 0x7F
    imm4_0 = offset & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (2 << 12) | (imm4_0 << 7) | 0x23

def sb(rs2, rs1, offset):
    """SB rs2, offset(rs1)"""
    imm11_5 = (offset >> 5) & 0x7F
    imm4_0 = offset & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (imm4_0 << 7) | 0x23

def addi(rd, rs1, imm):
    """ADDI rd, rs1, imm"""
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13

def andi(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (7 << 12) | (rd << 7) | 0x13

def ori(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (6 << 12) | (rd << 7) | 0x13

def xori(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (4 << 12) | (rd << 7) | 0x13

def srli(rd, rs1, shamt):
    return ((shamt & 0x1F) << 20) | (rs1 << 15) | (5 << 12) | (rd << 7) | 0x13

def slli(rd, rs1, shamt):
    return ((shamt & 0x1F) << 20) | (rs1 << 15) | (1 << 12) | (rd << 7) | 0x13

def add(rd, rs1, rs2):
    return (0 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x33

def sub(rd, rs1, rs2):
    return (0x20 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x33

def mul(rd, rs1, rs2):
    return (0x01 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x33

def divu(rd, rs1, rs2):
    return (0x01 << 25) | (rs2 << 20) | (rs1 << 15) | (5 << 12) | (rd << 7) | 0x33

def remu(rd, rs1, rs2):
    return (0x01 << 25) | (rs2 << 20) | (rs1 << 15) | (7 << 12) | (rd << 7) | 0x33

def or_(rd, rs1, rs2):
    return (0 << 25) | (rs2 << 20) | (rs1 << 15) | (6 << 12) | (rd << 7) | 0x33

def and_(rd, rs1, rs2):
    return (0 << 25) | (rs2 << 20) | (rs1 << 15) | (7 << 12) | (rd << 7) | 0x33

def nop():
    return addi(ZERO, ZERO, 0)

# ---------------------------------------------------------------------------
# 辅助：li (load immediate, 32-bit)
# ---------------------------------------------------------------------------
def li(rd, value):
    """加载32位立即数，生成1-2条指令"""
    value &= 0xFFFFFFFF
    if value == 0:
        return [addi(rd, ZERO, 0)]
    elif value < 0x800 and value >= 0:
        return [addi(rd, ZERO, value)]
    elif (value & 0xFFF) == 0:
        return [lui(rd, (value >> 12) & 0xFFFFF)]
    else:
        upper = (value + 0x800) >> 12  # 加0x800处理符号扩展
        upper &= 0xFFFFF
        lower = value & 0xFFF
        return [lui(rd, upper), addi(rd, rd, lower if lower < 0x800 else lower - 0x1000)]

# ============================================================================
# 两遍汇编器：支持标签
# ============================================================================

class Program:
    def __init__(self):
        self.items = []  # [(type, data)]  type: 'instr' or 'label'
    
    def emit(self, instr):
        """添加一条已编码的指令（32位整数）"""
        self.items.append(('instr', instr))
    
    def emit_list(self, instrs):
        """添加多条指令"""
        for i in instrs:
            self.items.append(('instr', i))
    
    def label(self, name):
        """定义标签"""
        self.items.append(('label', name))
    
    def emit_branch(self, rs1, rs2, target_label, funct3_func):
        """添加带标签引用的分支指令（第二遍解析）"""
        self.items.append(('branch', (rs1, rs2, target_label, funct3_func)))
    
    def emit_jal(self, rd, target_label):
        """添加带标签引用的JAL指令"""
        self.items.append(('jal_ref', (rd, target_label)))
    
    def pad_nop(self, count):
        """填充count个NOP"""
        for _ in range(count):
            self.items.append(('instr', nop()))
    
    def assemble(self):
        """两遍汇编，返回hex字符串列表"""
        # Pass 1: 计算标签地址
        labels = {}
        addr = 0
        for item_type, data in self.items:
            if item_type == 'label':
                labels[data] = addr
            else:
                addr += 4
        
        # Pass 2: 编码指令
        result = []
        addr = 0
        for item_type, data in self.items:
            if item_type == 'label':
                continue
            elif item_type == 'instr':
                result.append(data)
            elif item_type == 'branch':
                rs1, rs2, target_label, func = data
                offset = labels[target_label] - addr
                result.append(func(rs1, rs2, offset))
            elif item_type == 'jal_ref':
                rd, target_label = data
                offset = labels[target_label] - addr
                result.append(jal(rd, offset))
            addr += 4
        
        return result

# ============================================================================
# 公共代码：UART发送函数 + 报告函数
# ============================================================================

def gen_uart_send_byte(prog):
    """
    生成 send_byte 函数：
    输入: A5 = 要发送的字节
    使用: T0 = UART base, A4 = 临时
    返回: 无
    """
    prog.label('send_byte')
    # 等待 UART 空闲
    prog.label('sb_wait')
    prog.emit(lw(A4, T0, 4))         # A4 = TXSTAT
    prog.emit(andi(A4, A4, 1))       # 检查 tx_busy
    prog.emit_branch(A4, ZERO, 'sb_wait', bne)  # busy则继续等待
    # 发送字节
    prog.emit(sb(A5, T0, 0))          # 写 TXDATA
    prog.emit(jalr(ZERO, RA, 0))      # return

def gen_send_u32(prog):
    """send_u32（二进制模式）"""
    prog.label('send_u32')
    prog.emit(addi(S1, A5, 0))       # save value
    prog.emit(addi(S2, RA, 0))       # save RA (critical!)
    prog.emit(srli(A5, S1, 24))
    prog.emit(andi(A5, A5, 0xFF))
    prog.emit_jal(RA, 'send_byte')
    prog.emit(srli(A5, S1, 16))
    prog.emit(andi(A5, A5, 0xFF))
    prog.emit_jal(RA, 'send_byte')
    prog.emit(srli(A5, S1, 8))
    prog.emit(andi(A5, A5, 0xFF))
    prog.emit_jal(RA, 'send_byte')
    prog.emit(andi(A5, S1, 0xFF))
    prog.emit_jal(RA, 'send_byte')
    prog.emit(addi(A5, S1, 0))       # restore A5
    prog.emit(addi(RA, S2, 0))       # restore RA
    prog.emit(jalr(ZERO, RA, 0))

def gen_send_decimal(prog):
    """
    send_decimal: 发送A5的十进制ASCII表示
    输入: A5 = 无符号整数
    使用: S1=value, S2=save RA, A4=digit, T2=除数, S0=前导零标志
    """
    prog.label('send_decimal')
    prog.emit(addi(S1, A5, 0))         # S1 = value
    prog.emit(addi(S2, RA, 0))         # S2 = save RA (critical!)
    prog.emit(addi(S0, ZERO, 0))       # S0 = 0 (leading zero flag)
    prog.emit_list(li(T2, 1000000000))

    prog.label('sd_loop')
    prog.emit_branch(T2, ZERO, 'sd_done', beq)
    prog.emit(divu(A4, S1, T2))
    prog.emit(remu(S1, S1, T2))
    prog.emit_list(li(A5, 10))
    prog.emit(divu(T2, T2, A5))
    prog.emit_branch(A4, ZERO, 'sd_check_lead', beq)
    prog.emit(addi(S0, ZERO, 1))
    prog.label('sd_send_digit')
    prog.emit(addi(A5, A4, 48))
    prog.emit_jal(RA, 'send_byte')
    prog.emit_jal(ZERO, 'sd_loop')
    prog.label('sd_check_lead')
    prog.emit_branch(S0, ZERO, 'sd_loop', beq)
    prog.emit(addi(A5, ZERO, 48))
    prog.emit_jal(RA, 'send_byte')
    prog.emit_jal(ZERO, 'sd_loop')
    prog.label('sd_done')
    prog.emit_branch(S0, ZERO, 'sd_return', bne)
    prog.emit(addi(A5, ZERO, 48))
    prog.emit_jal(RA, 'send_byte')
    prog.label('sd_return')
    prog.emit(addi(RA, S2, 0))         # restore RA
    prog.emit(jalr(ZERO, RA, 0))

def gen_report_and_halt(prog, test_marker=0x4C):
    """
    ASCII文本报告：输出可读格式到UART
    格式: L:hit=79992,miss=80,total=80072,rate=999\n
    """
    # 1. 先计算命中率并写入LED
    prog.emit(add(A2, A0, A1))
    prog.emit(addi(A3, ZERO, 1000))
    prog.emit(mul(A3, A0, A3))
    prog.emit(beq(A2, ZERO, 4))
    prog.emit(divu(A3, A3, A2))
    prog.emit(sw(A3, T1, 0))

    # 1.5 写快照寄存器到GPIO（数码管显示用，与UART输出一致）
    prog.emit(sw(A0, T1, 8))    # GPIO+0x08 = snap_hit
    prog.emit(sw(A1, T1, 12))   # GPIO+0x0C = snap_miss
    prog.emit(sw(A2, T1, 16))   # GPIO+0x10 = snap_total

    # 2. UART发送ASCII报告
    # 发送标记字符
    marker_char = chr(test_marker)
    prog.emit(addi(A5, ZERO, test_marker))
    prog.emit_jal(RA, 'send_byte')
    # 发送 ":hit="
    for ch in ":hit=":
        prog.emit(addi(A5, ZERO, ord(ch)))
        prog.emit_jal(RA, 'send_byte')
    # 发送 hit_delta
    prog.emit(addi(A5, A0, 0))
    prog.emit_jal(RA, 'send_decimal')
    # 发送 ",miss="
    for ch in ",miss=":
        prog.emit(addi(A5, ZERO, ord(ch)))
        prog.emit_jal(RA, 'send_byte')
    # 发送 miss_delta
    prog.emit(addi(A5, A1, 0))
    prog.emit_jal(RA, 'send_decimal')
    # 发送 ",total="
    for ch in ",total=":
        prog.emit(addi(A5, ZERO, ord(ch)))
        prog.emit_jal(RA, 'send_byte')
    # 发送 total
    prog.emit(addi(A5, A2, 0))
    prog.emit_jal(RA, 'send_decimal')
    # 发送 ",rate="
    for ch in ",rate=":
        prog.emit(addi(A5, ZERO, ord(ch)))
        prog.emit_jal(RA, 'send_byte')
    # 发送 rate (千分比)
    prog.emit(addi(A5, A3, 0))
    prog.emit_jal(RA, 'send_decimal')
    # 发送 "\r\n"
    prog.emit(addi(A5, ZERO, 0x0D))
    prog.emit_jal(RA, 'send_byte')
    prog.emit(addi(A5, ZERO, 0x0A))
    prog.emit_jal(RA, 'send_byte')

    # 3. 死循环
    prog.label('halt')
    prog.emit_jal(ZERO, 'halt')

def add_li_1000(prog):
    """在Program类中添加加载1000的方法"""
    prog.emit(addi(A3, ZERO, 1000))

# 给Program类添加方法
Program.emit_li_1000 = add_li_1000

# ============================================================================
# 测试程序生成器
# ============================================================================

def gen_setup(prog):
    """公共初始化代码"""
    # T0 = UART base (0x10000000)
    prog.emit_list(li(T0, UART_BASE))
    # T1 = GPIO base (0x10010000)
    prog.emit_list(li(T1, GPIO_BASE))
    # T2 = PERF base (0x10030000)
    prog.emit_list(li(T2, PERF_BASE))
    
    # 读取初始计数器
    prog.emit(lw(A0, T2, PERF_HIT))    # A0 = initial hit_count
    prog.emit(lw(A1, T2, PERF_MISS))   # A1 = initial miss_count

def gen_read_final(prog):
    """读取最终计数器并计算delta"""
    prog.emit(lw(A3, T2, PERF_HIT))    # A3 = final hit_count
    prog.emit(lw(A4, T2, PERF_MISS))   # A4 = final miss_count
    prog.emit(sub(A0, A3, A0))         # A0 = hit_delta
    prog.emit(sub(A1, A4, A1))         # A1 = miss_delta

def gen_test_loop():
    """
    测试1：紧凑循环
    4指令循环体 × 10000次迭代
    循环体仅16字节，远小于cache，命中率应接近100%
    """
    prog = Program()
    
    # === 初始化 ===
    gen_setup(prog)
    
    # === 测试模式：紧凑循环 ===
    prog.emit_list(li(A2, 10000))      # A2 = 循环次数
    prog.label('loop_start')
    prog.emit(nop())                   # 循环体：4条NOP
    prog.emit(nop())
    prog.emit(nop())
    prog.emit(nop())
    prog.emit(addi(A2, A2, -1))       # A2--
    prog.emit_branch(A2, ZERO, 'loop_start', bne)  # 循环
    
    # === 读取结果 ===
    gen_read_final(prog)
    
    # 跳过函数定义，直接到报告代码
    prog.emit_jal(ZERO, 'do_report')
    
    # === UART 函数定义（不会被 fall-through 执行）===
    gen_uart_send_byte(prog)
    gen_send_u32(prog)
    gen_send_decimal(prog)
    
    # === 报告代码 ===
    prog.label('do_report')
    gen_report_and_halt(prog, test_marker=0x4C)  # 'L'
    
    return prog.assemble()

def gen_test_sequential():
    """
    测试2：顺序执行
    512条NOP（2048字节，与cache大小相同）
    测试流式预取和流式旁路的效果
    """
    prog = Program()
    
    # === 初始化 ===
    gen_setup(prog)
    
    # === 测试模式：顺序执行512条NOP ===
    prog.pad_nop(512)
    
    # === 读取结果 ===
    gen_read_final(prog)
    
    # 跳过函数定义，直接到报告代码
    prog.emit_jal(ZERO, 'do_report')
    
    # === UART 函数定义 ===
    gen_uart_send_byte(prog)
    gen_send_u32(prog)
    gen_send_decimal(prog)
    
    # === 报告代码 ===
    prog.label('do_report')
    gen_report_and_halt(prog, test_marker=0x53)  # 'S'
    
    return prog.assemble()

def gen_test_branchy():
    """
    测试3：分支密集
    交替跳转到相隔较远的地址（间隔64字节=16指令）
    100次迭代，每次跳转2个不同地址
    """
    prog = Program()
    
    # === 初始化 ===
    gen_setup(prog)
    
    # === 测试模式：分支密集 ===
    prog.emit_list(li(A2, 100))       # A2 = 迭代次数
    
    prog.label('br_loop')
    # 跳转到 target_a (向前 64 字节 = 16 条指令)
    prog.emit_branch(ZERO, ZERO, 'target_a', beq)  # BEQ x0,x0,target_a
    prog.pad_nop(14)                  # 填充（不会执行）
    
    prog.label('target_a')
    # 跳转到 target_b (再向前 64 字节)
    prog.emit_branch(ZERO, ZERO, 'target_b', beq)
    prog.pad_nop(14)
    
    prog.label('target_b')
    prog.emit(addi(A2, A2, -1))
    prog.emit_branch(A2, ZERO, 'br_loop', bne)
    
    # === 读取结果 ===
    gen_read_final(prog)
    
    # 跳过函数定义，直接到报告代码
    prog.emit_jal(ZERO, 'do_report')
    
    # === UART 函数定义 ===
    gen_uart_send_byte(prog)
    gen_send_u32(prog)
    gen_send_decimal(prog)
    
    # === 报告代码 ===
    prog.label('do_report')
    gen_report_and_halt(prog, test_marker=0x42)  # 'B'
    
    return prog.assemble()

def gen_test_mixed():
    """
    测试4：混合模式
    顺序200条 + 紧凑循环500次 + 分支50次
    模拟真实程序的混合访问模式
    """
    prog = Program()
    
    # === 初始化 ===
    gen_setup(prog)
    
    # === 阶段1：顺序执行200条NOP ===
    prog.pad_nop(200)
    
    # === 阶段2：紧凑循环500次 ===
    prog.emit_list(li(A2, 500))
    prog.label('mixed_loop')
    prog.emit(nop())
    prog.emit(nop())
    prog.emit(addi(A2, A2, -1))
    prog.emit_branch(A2, ZERO, 'mixed_loop', bne)
    
    # === 阶段3：分支50次 ===
    prog.emit_list(li(A2, 50))
    prog.label('mixed_br')
    prog.emit_branch(ZERO, ZERO, 'mixed_tgt', beq)
    prog.pad_nop(6)
    prog.label('mixed_tgt')
    prog.emit(addi(A2, A2, -1))
    prog.emit_branch(A2, ZERO, 'mixed_br', bne)
    
    # === 读取结果 ===
    gen_read_final(prog)
    
    # 跳过函数定义，直接到报告代码
    prog.emit_jal(ZERO, 'do_report')
    
    # === UART 函数定义 ===
    gen_uart_send_byte(prog)
    gen_send_u32(prog)
    gen_send_decimal(prog)
    
    # === 报告代码 ===
    prog.label('do_report')
    gen_report_and_halt(prog, test_marker=0x4D)  # 'M'
    
    return prog.assemble()

# ============================================================================
# hex 文件输出
# ============================================================================

def write_hex(instructions, filename):
    """将指令列表写入 $readmemh 格式的 hex 文件"""
    filepath = os.path.join(SCRIPT_DIR, filename)
    with open(filepath, 'w') as f:
        for instr in instructions:
            # 每行一个32位十六进制数
            f.write(f'{instr & 0xFFFFFFFF:08X}\n')
    print(f'  生成: {filepath} ({len(instructions)} 条指令 = {len(instructions)*4} 字节)')

def gen_test_gpio():
    """
    最小测试：写 0xAA (10101010) 到 LED 然后 halt
    用于验证 GPIO 是否工作
    """
    prog = Program()
    # T1 = GPIO base
    prog.emit_list(li(T1, GPIO_BASE))
    # A3 = 0xAA = 170
    prog.emit(addi(A3, ZERO, 0xAA))
    # 写 LED
    prog.emit(sw(A3, T1, 0))
    # halt
    prog.label('halt')
    prog.emit_jal(ZERO, 'halt')
    return prog.assemble()

def gen_test_read_hit():
    """
    最小测试2：读 hit_count 写到 LED
    用于验证 MMIO 读取是否工作
    """
    prog = Program()
    # T2 = PERF base
    prog.emit_list(li(T2, PERF_BASE))
    # T1 = GPIO base
    prog.emit_list(li(T1, GPIO_BASE))
    # A3 = hit_count
    prog.emit(lw(A3, T2, PERF_HIT))
    # 写 LED (低16位)
    prog.emit(sw(A3, T1, 0))
    # halt
    prog.label('halt')
    prog.emit_jal(ZERO, 'halt')
    return prog.assemble()

def gen_test_large():
    """
    测试6：大指令量测试（6KB = 1536条指令）
    包含多种指令模式：顺序NOP、嵌套循环、分支跳转
    填满更多cache行，测试PMRU替换策略在大工作集下的表现
    """
    prog = Program()

    # === 初始化 ===
    gen_setup(prog)

    # === 阶段1: 384条顺序NOP（填充96个cache行）===
    prog.pad_nop(384)

    # === 阶段2: 嵌套循环（外层30次×内层50次，循环体4条指令）===
    prog.emit_list(li(A2, 30))         # 外层循环计数
    prog.label('outer_loop')
    prog.emit_list(li(A3, 50))         # 内层循环计数
    prog.label('inner_loop')
    prog.emit(nop())
    prog.emit(nop())
    prog.emit(addi(A3, A3, -1))
    prog.emit_branch(A3, ZERO, 'inner_loop', bne)
    prog.emit(addi(A2, A2, -1))
    prog.emit_branch(A2, ZERO, 'outer_loop', bne)

    # === 阶段3: 192条顺序NOP（48个cache行）===
    prog.pad_nop(192)

    # === 阶段4: 远跳转模式（交替跳转，间隔16条指令）===
    prog.emit_list(li(A2, 30))
    prog.label('branch_start')
    prog.emit_jal(ZERO, 'far_target_1')
    prog.pad_nop(14)
    prog.label('far_target_1')
    prog.emit_jal(ZERO, 'far_target_2')
    prog.pad_nop(14)
    prog.label('far_target_2')
    prog.emit(addi(A2, A2, -1))
    prog.emit_branch(A2, ZERO, 'branch_start', bne)

    # === 阶段5: 顺序NOP填充到接近1536条指令 ===
    # 当前已有: setup(~10) + 384 + ~10 + 192 + ~80 = ~676
    # 需要再填充约840条NOP
    prog.pad_nop(840)

    # === 读取结果 ===
    gen_read_final(prog)

    # 跳过函数定义，直接到报告代码
    prog.emit_jal(ZERO, 'do_report')

    # === UART 函数定义 ===
    gen_uart_send_byte(prog)
    gen_send_u32(prog)
    gen_send_decimal(prog)

    # === 报告代码 ===
    prog.label('do_report')
    gen_report_and_halt(prog, test_marker=0x42)  # 'B' = Big

    return prog.assemble()

def gen_test_thrash():
    """
    压力测试：严重冲突缺失 + 容量缺失
    Phase 1: 16个代码块映射到同一cache set（间隔64条指令）
             8路组相联 → 16个地址争8个槽 → 每轮8+次冲突缺失
    Phase 2: 900条顺序NOP，超出512条指令的cache容量 → 容量缺失
    Cache: 64组 × 8路 × 4字节 = 2KB = 512条指令
    指令存储器: 2048字 = 8KB
    """
    prog = Program()

    # === 初始化 ===
    gen_setup(prog)

    # === Phase 1: 冲突缺失测试 ===
    # 16个块，每块64条指令间隔 → 全部映射到同一cache set
    # 每块: 1 NOP(有用) + 1 JAL(跳转) + 62 NOP(填充,不执行)
    prog.emit_list(li(A2, 20))          # 20轮迭代
    prog.label('thrash_loop')

    for i in range(15):
        prog.label(f'blk{i}')
        prog.emit(nop())                 # 有用指令
        prog.emit_jal(ZERO, f'blk{i+1}') # 跳到下一块
        prog.pad_nop(62)                 # 填充到64条指令间隔

    # 第16块：递减计数器，循环或退出
    prog.label('blk15')
    prog.emit(nop())
    prog.emit(addi(A2, A2, -1))
    prog.emit_branch(A2, ZERO, 'thrash_loop', bne)

    # === Phase 2: 容量缺失测试 ===
    # 900条顺序NOP，cache只能存512条 → 超出部分全部miss
    prog.pad_nop(900)

    # === 读取结果 ===
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
    print('PMRU8 I-Cache 板载测试程序生成器')
    print('=' * 50)
    
    tests = [
        ('test_gpio.hex',       gen_test_gpio,       'GPIO最小测试 (写0xAA到LED)'),
        ('test_read_hit.hex',   gen_test_read_hit,   '读hit_count写LED (验证MMIO)'),
        ('test_loop.hex',       gen_test_loop,       '紧凑循环 (4指令×10000次)'),
        ('test_sequential.hex', gen_test_sequential, '顺序执行 (512条NOP)'),
        ('test_branchy.hex',    gen_test_branchy,    '分支密集 (交替远跳转)'),
        ('test_mixed.hex',      gen_test_mixed,      '混合模式 (顺序+循环+分支)'),
        ('test_large.hex',      gen_test_large,      '大指令量6KB (1536条混合指令)'),
        ('test_thrash.hex',     gen_test_thrash,     '压力测试 (冲突缺失+容量缺失)'),
    ]
    
    for filename, gen_func, desc in tests:
        print(f'\n[{desc}]')
        instrs = gen_func()
        write_hex(instrs, filename)
        if len(instrs) > 2048:
            print(f'  警告: 程序超过2048字（8KB）限制！当前: {len(instrs)}字')
    
    print('\n' + '=' * 50)
    print('调试步骤:')
    print('  1. 先烧 test_gpio.hex — LED应显示 0x00AA (交替亮灭)')
    print('     如果LED不亮 → GPIO/综合有问题')
    print('  2. 再烧 test_read_hit.hex — LED应显示 hit_count 低16位')
    print('     如果LED不亮 → MMIO读取有问题')
    print('  3. 最后烧 test_loop.hex — LED应显示命中率 (0-1000)')

if __name__ == '__main__':
    main()
