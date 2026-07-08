#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RV32IM 轻量级汇编器 —— 用于生成性能测试 hex 文件
支持两遍汇编：第一遍计算标签地址，第二遍编码指令。
输出格式兼容 Verilog $readmemh。
"""

import sys
import re

# ============================================================
# 寄存器名映射
# ============================================================
REG_NAMES = {
    'x0':0,'zero':0,'x1':1,'ra':1,'x2':2,'sp':2,'x3':3,'gp':3,
    'x4':4,'tp':4,'x5':5,'t0':5,'x6':6,'t1':6,'x7':7,'t2':7,
    'x8':8,'s0':8,'fp':8,'x9':9,'s1':9,'x10':10,'a0':10,
    'x11':11,'a1':11,'x12':12,'a2':12,'x13':13,'a3':13,
    'x14':14,'a4':14,'x15':15,'a5':15,'x16':16,'a6':16,
    'x17':17,'a7':17,'x18':18,'s2':18,'x19':19,'s3':19,
    'x20':20,'s4':20,'x21':21,'s5':21,'x22':22,'s6':22,
    'x23':23,'s7':23,'x24':24,'s8':24,'x25':25,'s9':25,
    'x26':26,'s10':26,'x27':27,'s11':27,'x28':28,'t3':28,
    'x29':29,'t4':29,'x30':30,'t5':30,'x31':31,'t6':31,
}

def parse_reg(tok):
    tok = tok.strip().rstrip(',')
    if tok not in REG_NAMES:
        raise ValueError(f"未知寄存器: {tok}")
    return REG_NAMES[tok]

def parse_imm(tok):
    tok = tok.strip().rstrip(',')
    if tok.startswith('0x') or tok.startswith('-0x'):
        return int(tok, 16)
    return int(tok, 0)

# ============================================================
# 指令编码器
# ============================================================

def encode_r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return (fununct7_val(funct7) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3_val(funct3) << 12) | (rd << 7) | opcode

def fununct7_val(s):
    return s if isinstance(s, int) else int(s, 0)

def funct3_val(s):
    return s if isinstance(s, int) else int(s, 0)

# 更直接的方式：每个指令一个编码函数
def enc_r_type(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_i_type(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_s_type(imm, rs2, rs1, funct3, opcode=0x23):
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return (imm11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | (imm4_0 << 7) | (opcode & 0x7F)

def enc_b_type(imm, rs2, rs1, funct3, opcode=0x63):
    # imm 是相对于当前指令的偏移（已计算好）
    imm = imm & 0x1FFF  # 13位
    b12 = (imm >> 12) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    b11 = (imm >> 11) & 1
    return (b12 << 31) | (b10_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | (b4_1 << 8) | (b11 << 7) | (opcode & 0x7F)

def enc_u_type(imm, rd, opcode):
    return (((imm >> 12) & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_j_type(imm, rd, opcode=0x6F):
    imm = imm & 0x1FFFFF  # 21位
    b20 = (imm >> 20) & 1
    b10_1 = (imm >> 1) & 0x3FF
    b11 = (imm >> 11) & 1
    b19_12 = (imm >> 12) & 0xFF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)


# ============================================================
# 指令表
# ============================================================

# R-type: (funct7, funct3, opcode)
R_INSTR = {
    'add':  (0x00, 0x0, 0x33), 'sub': (0x20, 0x0, 0x33),
    'sll':  (0x00, 0x1, 0x33), 'slt': (0x00, 0x2, 0x33),
    'sltu': (0x00, 0x3, 0x33), 'xor': (0x00, 0x4, 0x33),
    'srl':  (0x00, 0x5, 0x33), 'sra': (0x20, 0x5, 0x33),
    'or':   (0x00, 0x6, 0x33), 'and': (0x00, 0x7, 0x33),
    # M 扩展
    'mul':  (0x01, 0x0, 0x33), 'mulh': (0x01, 0x1, 0x33),
    'div':  (0x01, 0x4, 0x33), 'divu': (0x01, 0x5, 0x33),
    'rem':  (0x01, 0x6, 0x33), 'remu': (0x01, 0x7, 0x33),
}

# I-type ALU: (funct3, opcode)
I_ALU_INSTR = {
    'addi':  (0x0, 0x13), 'slti':  (0x2, 0x13), 'sltiu': (0x3, 0x13),
    'xori':  (0x4, 0x13), 'ori':   (0x6, 0x13), 'andi':  (0x7, 0x13),
}

# I-type shift: (funct7, funct3, opcode)
I_SHIFT_INSTR = {
    'slli': (0x00, 0x1, 0x13), 'srli': (0x00, 0x5, 0x13), 'srai': (0x20, 0x5, 0x13),
}

# Load: (funct3, opcode=0x03)
LOAD_INSTR = {
    'lb': (0x0, 0x03), 'lh': (0x1, 0x03), 'lw': (0x2, 0x03),
    'lbu': (0x4, 0x03), 'lhu': (0x5, 0x03),
}

# Store: (funct3, opcode=0x23)
STORE_INSTR = {
    'sb': (0x0, 0x23), 'sh': (0x1, 0x23), 'sw': (0x2, 0x23),
}

# Branch: (funct3, opcode=0x63)
BRANCH_INSTR = {
    'beq': (0x0, 0x63), 'bne': (0x1, 0x63),
    'blt': (0x4, 0x63), 'bge': (0x5, 0x63),
    'bltu': (0x6, 0x63), 'bgeu': (0x7, 0x63),
}

# ============================================================
# 控制流指令集合 —— CPU 有延迟槽行为，这些指令后需插入 NOP
# ============================================================
CONTROL_FLOW_OPS = {
    # 标准分支
    'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu',
    # 伪指令分支
    'bnez', 'beqz', 'bgez', 'bltz', 'blez', 'bgtz',
    'ble', 'bgt',
    # 跳转
    'j', 'jr', 'ret', 'jal', 'jalr',
}


def is_control_flow(line):
    """判断一行是否包含控制流指令（需要在其后插入延迟槽 NOP）"""
    line = line.split('#')[0].strip()
    if not line:
        return False
    if line.startswith('.word'):
        return False
    # 处理 "label: instruction" 同行情况
    instr = line
    if ':' in instr and not instr.startswith('.'):
        parts = instr.split(':', 1)
        instr = parts[1].strip()
    if not instr:
        return False
    tokens = instr.replace(',', ' ').split()
    if not tokens:
        return False
    return tokens[0].lower() in CONTROL_FLOW_OPS


def to_hex32(val):
    """返回 8 位十六进制字符串（小端序：每行一个 32 位字）"""
    return f"{val & 0xFFFFFFFF:08x}"


# ============================================================
# 两遍汇编器
# ============================================================

class Assembler:
    def __init__(self):
        self.labels = {}
        self.instructions = []  # (line_text, addr)
        self.data_words = []    # (value, addr)
        self.base_addr = 0
        self.output = []

    def assemble(self, source_lines):
        """汇编源代码，返回 hex 行列表"""
        # --- 预处理：在控制流指令后自动插入 NOP（延迟槽填充）---
        # CPU 有延迟槽行为：分支/跳转指令后的下一条指令总是执行。
        # 若不插入 NOP，延迟槽会执行意外的真实指令，破坏程序语义。
        processed = []
        for line in source_lines:
            processed.append(line)
            if is_control_flow(line):
                processed.append('nop  # auto-inserted delay slot')

        source_lines = processed

        # --- 第一遍：收集标签和地址 ---
        addr = 0
        parsed = []  # (type, content, addr)  type: 'instr' or 'data' or 'label'

        for line in source_lines:
            line = line.split('#')[0].strip()  # 去注释
            if not line:
                continue

            # 标签
            if line.endswith(':') and ' ' not in line and '\t' not in line:
                label = line[:-1].strip()
                self.labels[label] = addr
                continue

            # 标签 + 指令在同一行
            if ':' in line and not line.startswith('.'):
                parts = line.split(':', 1)
                label = parts[0].strip()
                self.labels[label] = addr
                line = parts[1].strip()
                if not line:
                    continue

            # 数据定义
            if line.startswith('.word'):
                vals = line[5:].strip().split(',')
                for v in vals:
                    v = v.strip()
                    if v:
                        parsed.append(('data', parse_imm(v), addr))
                        addr += 4
                continue

            # 指令
            parsed.append(('instr', line, addr))
            addr += 4

        # --- 第二遍：编码 ---
        hex_lines = []
        for typ, content, addr in parsed:
            if typ == 'data':
                hex_lines.append(to_hex32(content))
            else:
                val = self.encode_instruction(content, addr)
                hex_lines.append(to_hex32(val))

        return hex_lines

    def encode_instruction(self, line, addr):
        """编码单条指令"""
        # 解析操作码和操作数
        parts = line.replace(',', ' ').split()
        op = parts[0].lower()
        args = parts[1:]

        # --- 伪指令 ---
        if op == 'nop':
            return enc_i_type(0, 0, 0x0, 0, 0x13)  # addi x0, x0, 0
        if op == 'mv':
            rd = parse_reg(args[0])
            rs = parse_reg(args[1])
            return enc_i_type(0, rs, 0x0, rd, 0x13)  # addi rd, rs, 0
        if op == 'li':
            rd = parse_reg(args[0])
            imm = parse_imm(args[1])
            return self._li(rd, imm)
        if op == 'j':
            target = self.labels[args[0]]
            offset = target - addr
            return enc_j_type(offset, 0, 0x6F)  # jal x0, offset
        if op == 'jr':
            rs = parse_reg(args[0])
            return enc_i_type(0, rs, 0x0, 0, 0x67)  # jalr x0, rs, 0
        if op == 'ret':
            return enc_i_type(0, 1, 0x0, 0, 0x67)  # jalr x0, ra, 0
        if op == 'bnez':
            rs = parse_reg(args[0])
            target = self.labels[args[1]]
            offset = target - addr
            return enc_b_type(offset, 0, rs, 0x1, 0x63)  # bne rs, x0, offset
        if op == 'beqz':
            rs = parse_reg(args[0])
            target = self.labels[args[1]]
            offset = target - addr
            return enc_b_type(offset, 0, rs, 0x0, 0x63)  # beq rs, x0, offset
        if op == 'bgez':
            rs = parse_reg(args[0])
            target = self.labels[args[1]]
            offset = target - addr
            return enc_b_type(offset, 0, rs, 0x5, 0x63)  # bge rs, x0, offset
        if op == 'bltz':
            rs = parse_reg(args[0])
            target = self.labels[args[1]]
            offset = target - addr
            return enc_b_type(offset, 0, rs, 0x4, 0x63)  # blt rs, x0, offset
        if op == 'blez':
            rs = parse_reg(args[0])
            target = self.labels[args[1]]
            offset = target - addr
            # blez rs = bge x0, rs (0 >= rs ⟺ rs <= 0)
            # enc_b_type(imm, rs2, rs1, ...) → rs1=x0=0, rs2=rs
            return enc_b_type(offset, rs, 0, 0x5, 0x63)
        if op == 'bgtz':
            rs = parse_reg(args[0])
            target = self.labels[args[1]]
            offset = target - addr
            # bgtz rs = blt x0, rs (0 < rs ⟺ rs > 0)
            # enc_b_type(imm, rs2, rs1, ...) → rs1=x0=0, rs2=rs
            return enc_b_type(offset, rs, 0, 0x4, 0x63)
        if op == 'ble':
            rs1 = parse_reg(args[0])
            rs2 = parse_reg(args[1])
            target = self.labels[args[2]]
            offset = target - addr
            # ble rs1, rs2 = bge rs2, rs1
            return enc_b_type(offset, rs1, rs2, 0x5, 0x63)
        if op == 'bgt':
            rs1 = parse_reg(args[0])
            rs2 = parse_reg(args[1])
            target = self.labels[args[2]]
            offset = target - addr
            # bgt rs1, rs2 = blt rs2, rs1
            return enc_b_type(offset, rs1, rs2, 0x4, 0x63)

        # --- R-type ---
        if op in R_INSTR:
            funct7, funct3, opcode = R_INSTR[op]
            rd = parse_reg(args[0])
            rs1 = parse_reg(args[1])
            rs2 = parse_reg(args[2])
            return enc_r_type(funct7, rs2, rs1, funct3, rd, opcode)

        # --- I-type ALU ---
        if op in I_ALU_INSTR:
            funct3, opcode = I_ALU_INSTR[op]
            rd = parse_reg(args[0])
            rs1 = parse_reg(args[1])
            imm = parse_imm(args[2])
            return enc_i_type(imm, rs1, funct3, rd, opcode)

        # --- I-type shift ---
        if op in I_SHIFT_INSTR:
            funct7, funct3, opcode = I_SHIFT_INSTR[op]
            rd = parse_reg(args[0])
            rs1 = parse_reg(args[1])
            shamt = parse_imm(args[2]) & 0x1F
            return enc_i_type((funct7 << 5) | shamt, rs1, funct3, rd, opcode)

        # --- Load ---
        if op in LOAD_INSTR:
            funct3, opcode = LOAD_INSTR[op]
            rd = parse_reg(args[0])
            # args[1] = offset(rs1)
            m = re.match(r'(-?\w+)\((\w+)\)', args[1])
            if m:
                imm = parse_imm(m.group(1))
                rs1 = parse_reg(m.group(2))
            else:
                imm = 0
                rs1 = parse_reg(args[1])
            return enc_i_type(imm, rs1, funct3, rd, opcode)

        # --- Store ---
        if op in STORE_INSTR:
            funct3, opcode = STORE_INSTR[op]
            rs2 = parse_reg(args[0])
            m = re.match(r'(-?\w+)\((\w+)\)', args[1])
            if m:
                imm = parse_imm(m.group(1))
                rs1 = parse_reg(m.group(2))
            else:
                imm = 0
                rs1 = parse_reg(args[1])
            return enc_s_type(imm, rs2, rs1, funct3, opcode)

        # --- Branch ---
        if op in BRANCH_INSTR:
            funct3, opcode = BRANCH_INSTR[op]
            rs1 = parse_reg(args[0])
            rs2 = parse_reg(args[1])
            target = self.labels[args[2]]
            offset = target - addr
            return enc_b_type(offset, rs2, rs1, funct3, opcode)

        # --- JAL ---
        if op == 'jal':
            if args[0] in REG_NAMES:
                rd = parse_reg(args[0])
                target = self.labels[args[1]]
            else:
                rd = 1  # ra
                target = self.labels[args[0]]
            offset = target - addr
            return enc_j_type(offset, rd, 0x6F)

        # --- JALR ---
        if op == 'jalr':
            if len(args) == 1:
                rd = 1
                rs1 = parse_reg(args[0])
                imm = 0
            else:
                rd = parse_reg(args[0])
                m = re.match(r'(-?\w+)\((\w+)\)', args[1])
                if m:
                    imm = parse_imm(m.group(1))
                    rs1 = parse_reg(m.group(2))
                else:
                    rs1 = parse_reg(args[1])
                    imm = 0
            return enc_i_type(imm, rs1, 0x0, rd, 0x67)

        # --- LUI ---
        if op == 'lui':
            rd = parse_reg(args[0])
            imm = parse_imm(args[1])
            return enc_u_type(imm, rd, 0x37)

        # --- AUIPC ---
        if op == 'auipc':
            rd = parse_reg(args[0])
            imm = parse_imm(args[1])
            return enc_u_type(imm, rd, 0x17)

        # --- EBREAK ---
        if op == 'ebreak':
            return 0x00100073

        raise ValueError(f"不支持的指令: {op} {args}")

    def _li(self, rd, imm):
        """li 伪指令：小立即数用 addi，大立即数用 lui+addi"""
        if -2048 <= imm <= 2047:
            return enc_i_type(imm, 0, 0x0, rd, 0x13)  # addi rd, x0, imm
        elif 0 <= imm <= 0xFFFFF000:
            upper = (imm + 0x800) >> 12
            lower = imm & 0xFFF
            if lower >= 0x800:
                lower = lower - 0x1000
            # 生成 lui + addi 两条指令（返回第一条，第二条需要单独处理）
            # 简化处理：只用 lui + addi，但这里只能返回一条
            # 实际应在汇编时展开为两条
            raise ValueError("li 大立即数需要在源码中展开为 lui+addi")
        else:
            raise ValueError(f"立即数超出范围: {imm}")


# ============================================================
# 三个性能测试程序
# ============================================================

# 数据存储区基址（RAM 起始 0x00000000）
DATA_BASE = 0x00000000

# --- 程序 1：3x3 矩阵乘法（计算密集型）---
MATMUL_ASM = """
# ============================================================
# 3x3 矩阵乘法 C = A * B
# A, B 预存在内存中，C 写回内存
# 寄存器分配：
#   s0 = A 基址, s1 = B 基址, s2 = C 基址
#   a0 = i, a1 = j, a2 = k
#   t0 = A[i][k], t1 = B[k][j], t2 = acc
#   t3 = 字地址偏移
# ============================================================

# 初始化矩阵 A (3x3) 存入内存 0x000-0x020
# A = [[1,2,3],[4,5,6],[7,8,9]]
li t0, 1
sw t0, 0(x0)       # A[0][0]=1
li t0, 2
sw t0, 4(x0)       # A[0][1]=2
li t0, 3
sw t0, 8(x0)       # A[0][2]=3
li t0, 4
sw t0, 12(x0)      # A[1][0]=4
li t0, 5
sw t0, 16(x0)      # A[1][1]=5
li t0, 6
sw t0, 20(x0)      # A[1][2]=6
li t0, 7
sw t0, 24(x0)      # A[2][0]=7
li t0, 8
sw t0, 28(x0)      # A[2][1]=8
li t0, 9
sw t0, 32(x0)      # A[2][2]=9

# 初始化矩阵 B (3x3) 存入内存 0x040-0x060
# B = [[9,8,7],[6,5,4],[3,2,1]]
li t0, 9
sw t0, 64(x0)      # B[0][0]=9
li t0, 8
sw t0, 68(x0)      # B[0][1]=8
li t0, 7
sw t0, 72(x0)      # B[0][2]=7
li t0, 6
sw t0, 76(x0)      # B[1][0]=6
li t0, 5
sw t0, 80(x0)      # B[1][1]=5
li t0, 4
sw t0, 84(x0)      # B[1][2]=4
li t0, 3
sw t0, 88(x0)      # B[2][0]=3
li t0, 2
sw t0, 92(x0)      # B[2][1]=2
li t0, 1
sw t0, 96(x0)      # B[2][2]=1

# C 基址 = 0x080 (128)
li s2, 128          # s2 = C base

# 外层循环 i = 0..2
li a0, 0            # i = 0
loop_i:
    # 中层循环 j = 0..2
    li a1, 0        # j = 0
    loop_j:
        # acc = 0
        li t2, 0    # acc = 0

        # 内层循环 k = 0..2
        li a2, 0    # k = 0
        loop_k:
            # t0 = A[i][k] = *(A_base + (i*3+k)*4)
            # t3 = i*3+k
            li t4, 3
            mul t3, a0, t4    # t3 = i*3
            add t3, t3, a2    # t3 = i*3+k
            slli t3, t3, 2    # t3 = (i*3+k)*4  字偏移
            add t5, x0, t3    # t5 = A offset
            lw t0, 0(t5)      # t0 = A[i][k]

            # t1 = B[k][j] = *(B_base + (k*3+j)*4)
            li t4, 3
            mul t3, a2, t4    # t3 = k*3
            add t3, t3, a1    # t3 = k*3+j
            slli t3, t3, 2    # t3 = (k*3+j)*4
            li t4, 64         # B base = 0x40
            add t5, t4, t3    # t5 = B address
            lw t1, 0(t5)      # t1 = B[k][j]

            # acc += t0 * t1
            mul t4, t0, t1
            add t2, t2, t4    # acc += A[i][k] * B[k][j]

            # k++
            addi a2, a2, 1
            li t4, 3
            bne a2, t4, loop_k

        # C[i][j] = acc
        # addr = C_base + (i*3+j)*4
        li t4, 3
        mul t3, a0, t4    # i*3
        add t3, t3, a1    # i*3+j
        slli t3, t3, 2    # *4
        add t5, s2, t3    # C address
        sw t2, 0(t5)      # store acc

        # j++
        addi a1, a1, 1
        li t4, 3
        bne a1, t4, loop_j

    # i++
    addi a0, a0, 1
    li t4, 3
    bne a0, t4, loop_i

# 死循环结束
end:
    j end
"""

# --- 程序 2：冒泡排序（分支密集型）---
BUBBLE_ASM = """
# ============================================================
# 冒泡排序：对 8 个元素升序排序
# 寄存器分配：
#   s0 = 数组基址, s1 = n (8)
#   a0 = i (外层), a1 = j (内层)
#   t0 = arr[j], t1 = arr[j+1], t2 = temp
# ============================================================

# 初始化数组（8 个元素）存入内存 0x000-0x01C
# arr = [5, 2, 8, 1, 9, 3, 7, 4]
li t0, 5
sw t0, 0(x0)
li t0, 2
sw t0, 4(x0)
li t0, 8
sw t0, 8(x0)
li t0, 1
sw t0, 12(x0)
li t0, 9
sw t0, 16(x0)
li t0, 3
sw t0, 20(x0)
li t0, 7
sw t0, 24(x0)
li t0, 4
sw t0, 28(x0)

li s1, 8            # n = 8
li a0, 0            # i = 0

# 外层循环：i = 0 to n-2
outer_loop:
    # 内层循环边界：j < n-1-i
    sub t3, s1, a0      # t3 = n - i
    addi t3, t3, -1     # t3 = n - 1 - i
    li a1, 0            # j = 0

inner_loop:
    # 比较 j 和 n-1-i
    bge a1, t3, inner_end

    # t0 = arr[j]
    slli t4, a1, 2      # t4 = j * 4
    lw t0, 0(t4)        # t0 = arr[j]

    # t1 = arr[j+1]
    addi t5, a1, 1
    slli t4, t5, 2      # t4 = (j+1) * 4
    lw t1, 0(t4)        # t1 = arr[j+1]

    # if arr[j] > arr[j+1], swap
    ble t0, t1, no_swap
    # swap: arr[j] = t1, arr[j+1] = t0
    slli t4, a1, 2      # j*4
    sw t1, 0(t4)        # arr[j] = t1 (smaller)
    addi t5, a1, 1
    slli t4, t5, 2      # (j+1)*4
    sw t0, 0(t4)        # arr[j+1] = t0 (larger)

no_swap:
    addi a1, a1, 1      # j++
    j inner_loop

inner_end:
    addi a0, a0, 1      # i++
    li t4, 7            # n-1 = 7
    bne a0, t4, outer_loop

# 死循环结束
end:
    j end
"""

# --- 程序 3：斐波那契数列（控制流密集型）---
FIBONACCI_ASM = """
# ============================================================
# 斐波那契数列：计算前 10 个斐波那契数并存入内存
# 寄存器分配：
#   a0 = 计数器 (0..9)
#   a1 = fib(i-1), a2 = fib(i)
#   t0 = fib(i+1), t1 = N(10)
# ============================================================

# fib(0) = 0, fib(1) = 1
li a1, 0            # prev = 0
li a2, 1            # curr = 1
li a0, 0            # counter = 0
li t1, 10           # N = 10

# 存储 fib(0)
sw a1, 0(x0)        # mem[0] = 0

fib_loop:
    # 存储当前值
    slli t2, a0, 2      # t2 = counter * 4
    sw a2, 0(t2)        # mem[counter] = curr

    # 计算 next = prev + curr
    add t0, a1, a2      # t0 = prev + curr
    # prev = curr, curr = next
    add a1, x0, a2      # prev = curr
    add a2, x0, t0      # curr = next

    # counter++
    addi a0, a0, 1
    bne a0, t1, fib_loop

# 死循环结束
end:
    j end
"""


# ============================================================
# 优化版程序：指令调度消除 Load-Use 停顿
# ============================================================

# --- 优化版程序 1：矩阵乘法（指令调度）---
# 优化点：将 addi a2, a2, 1 (k++) 从 mul/add 之后移到 lw t1 与 mul 之间，
#         填充 Load-Use 停顿槽，消除 27 次 Load-Use 停顿。
MATMUL_OPT_ASM = """
# ============================================================
# 3x3 矩阵乘法 C = A * B（指令调度优化版）
# 优化：内层循环中 lw t1 → mul t4 之间存在 Load-Use 冒险，
#       将 addi a2, a2, 1 (k++) 移至 lw t1 与 mul t4 之间填充停顿槽。
# ============================================================

# 初始化矩阵 A (3x3) 存入内存 0x000-0x020
li t0, 1
sw t0, 0(x0)
li t0, 2
sw t0, 4(x0)
li t0, 3
sw t0, 8(x0)
li t0, 4
sw t0, 12(x0)
li t0, 5
sw t0, 16(x0)
li t0, 6
sw t0, 20(x0)
li t0, 7
sw t0, 24(x0)
li t0, 8
sw t0, 28(x0)
li t0, 9
sw t0, 32(x0)

# 初始化矩阵 B (3x3) 存入内存 0x040-0x060
li t0, 9
sw t0, 64(x0)
li t0, 8
sw t0, 68(x0)
li t0, 7
sw t0, 72(x0)
li t0, 6
sw t0, 76(x0)
li t0, 5
sw t0, 80(x0)
li t0, 4
sw t0, 84(x0)
li t0, 3
sw t0, 88(x0)
li t0, 2
sw t0, 92(x0)
li t0, 1
sw t0, 96(x0)

li s2, 128          # s2 = C base
li a0, 0            # i = 0
loop_i:
    li a1, 0        # j = 0
    loop_j:
        li t2, 0    # acc = 0
        li a2, 0    # k = 0
        loop_k:
            li t4, 3
            mul t3, a0, t4
            add t3, t3, a2
            slli t3, t3, 2
            add t5, x0, t3
            lw t0, 0(t5)

            li t4, 3
            mul t3, a2, t4
            add t3, t3, a1
            slli t3, t3, 2
            li t4, 64
            add t5, t4, t3
            lw t1, 0(t5)

            # === 指令调度优化 ===
            # addi a2, a2, 1 从 mul/add 之后移到此处，填充 Load-Use 停顿槽
            addi a2, a2, 1    # k++ (independent of t1, fills stall slot)
            mul t4, t0, t1    # t1 now ready (forwarded from MEM/WB)
            add t2, t2, t4

            li t4, 3
            bne a2, t4, loop_k

        li t4, 3
        mul t3, a0, t4
        add t3, t3, a1
        slli t3, t3, 2
        add t5, s2, t3
        sw t2, 0(t5)

        addi a1, a1, 1
        li t4, 3
        bne a1, t4, loop_j

    addi a0, a0, 1
    li t4, 3
    bne a0, t4, loop_i

end:
    j end
"""

# --- 优化版程序 2：冒泡排序（指令调度）---
# 优化点：将 slli t4, a1, 2 (交换用的 j*4) 从 ble 之后移到 lw t1 与 ble 之间，
#         填充 Load-Use 停顿槽，消除 28 次 Load-Use 停顿。
BUBBLE_OPT_ASM = """
# ============================================================
# 冒泡排序（指令调度优化版）
# 优化：内层循环中 lw t1 → ble t0,t1 之间存在 Load-Use 冒险，
#       将 slli t4, a1, 2 (j*4，交换代码用) 移至 lw t1 与 ble 之间填充停顿槽。
# ============================================================

li t0, 5
sw t0, 0(x0)
li t0, 2
sw t0, 4(x0)
li t0, 8
sw t0, 8(x0)
li t0, 1
sw t0, 12(x0)
li t0, 9
sw t0, 16(x0)
li t0, 3
sw t0, 20(x0)
li t0, 7
sw t0, 24(x0)
li t0, 4
sw t0, 28(x0)

li s1, 8
li a0, 0

outer_loop:
    sub t3, s1, a0
    addi t3, t3, -1
    li a1, 0

inner_loop:
    bge a1, t3, inner_end

    slli t4, a1, 2
    lw t0, 0(t4)

    addi t5, a1, 1
    slli t4, t5, 2
    lw t1, 0(t4)

    # === 指令调度优化 ===
    # slli t4, a1, 2 (j*4) 从交换代码中移到此处，填充 Load-Use 停顿槽
    # 若 ble 跳转（无需交换），t4 结果不使用，无副作用
    # 若 ble 不跳转（需要交换），t4 已就绪，sw 直接使用
    slli t4, a1, 2      # j*4 (independent of t1, fills stall slot)
    ble t0, t1, no_swap  # t1 now ready (forwarded from MEM/WB)

    # swap:
    sw t1, 0(t4)        # arr[j] = t1 (t4 already computed)
    addi t5, a1, 1
    slli t4, t5, 2
    sw t0, 0(t4)        # arr[j+1] = t0

no_swap:
    addi a1, a1, 1
    j inner_loop

inner_end:
    addi a0, a0, 1
    li t4, 7
    bne a0, t4, outer_loop

end:
    j end
"""


def main():
    asm = Assembler()

    programs = [
        ('perf_matmul', MATMUL_ASM),
        ('perf_bubble', BUBBLE_ASM),
        ('perf_fib', FIBONACCI_ASM),
        ('perf_matmul_opt', MATMUL_OPT_ASM),
        ('perf_bubble_opt', BUBBLE_OPT_ASM),
        ('perf_fib_opt', FIBONACCI_ASM),  # 斐波那契无 Load-Use 停顿，无需优化
    ]

    import os
    out_dir = os.path.dirname(os.path.abspath(__file__))

    for name, source in programs:
        lines = source.strip().split('\n')
        try:
            hex_lines = asm.assemble(lines)
            out_path = os.path.join(out_dir, f'{name}.hex')
            with open(out_path, 'w') as f:
                for h in hex_lines:
                    f.write(h + '\n')
            print(f"[OK] {name}: {len(hex_lines)} words -> {out_path}")
        except Exception as e:
            print(f"[ERR] {name}: {e}")
            import traceback
            traceback.print_exc()

        # 重置汇编器状态
        asm = Assembler()


if __name__ == '__main__':
    main()
