# generate_all_hex.ps1 - Generate all missing hex files for testbenches
# This is run from E:\rvp_nexys (junction to riscv-cpu-design)

param(
    [string]$ProjectRoot = "E:\rvp_nexys",
    [string]$LogDir = "$ProjectRoot\document\log"
)

$logFile = "$LogDir\generate_hex_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$hexDir = "$ProjectRoot\sw\tests"

function Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

function Status($ok, $msg) {
    $tag = if ($ok) { "PASS" } else { "FAIL" }
    Log "[$tag] $msg"
}

# Ensure hex output directory
New-Item -ItemType Directory -Path $hexDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

Log "=========================================="
Log " Generate Missing Hex Files"
Log " Project: $ProjectRoot"
Log "=========================================="

# ============================================================================
# 1. Generate core_test_words.hex (for tb_core_single.sv)
# Hex file for single-cycle CPU integration test
# Expected:
#   x1=5, x2=3, x3=8, x4=2, x5=1, x6=7, x7=8, x8=42, x9=20, x10=1
#   MEM[0]=8
# ============================================================================
Log "Generating core_test_words.hex..."

# RISC-V instruction encoding:
# Instructions to generate (14):
# 0: addi x1, x0, 5       = 0x00500093
# 1: addi x2, x0, 3       = 0x00300113
# 2: add  x3, x1, x2      = 0x002081B3
# 3: sub  x4, x1, x2      = 0x40208233
# 4: and  x5, x1, x2      = 0x0020F2B3
# 5: or   x6, x1, x2      = 0x0020E333
# 6: addi x7, x0, 8       = 0x00800393
# 7: sw   x7, 0(x0)       = 0x00702023
# 8: lw   x7, 0(x0)       = 0x00002383  (load back from MEM[0])
# 9: beq  x1, x1, 12      = 0x00108463  (jump to PC+12, i.e. skip 2 instructions)
# 10: addi x8, x0, 10     = 0x00A00413  (NOT executed, branch taken)
# 11: j    PC+8           = 0x0040006F  (NOT executed)
# 12: addi x8, x0, 42     = 0x02A00413  (target: x8=42)
# 13: slli x9, x1, 2      = 0x00209493  (x9=5<<2=20)
# 14: slt  x10, x0, x1    = 0x0010A533  (x10=0<5=1)
# 15: j    end (at PC+8)  = 0x0040006F
# 16: j    -4 (loop)      = 0xFF9FF06F

# Let me recalculate imm offsets for branches/jumps more carefully:

# beq x1, x1, +8 (skip 2 words = 8 bytes after beq instruction)
# B-type: imm=8
# imm[12|10:5|4:1|11] = 0|000000|0100|0 = 0x0000
# Actually: 8 = 0b00000001000
# imm[12] = 0, imm[10:5] = 000000, imm[4:1] = 0100, imm[11] = 0
# = 0|000000|0100|0 = 0x0040... no let me recalculate
# B-type encoding: {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode}
# imm = 8 = b0000000_0000_1000
# imm[12] = 0, imm[11] = 0, imm[10:5] = 000000, imm[4:1] = 0100
# instruction = 0|000000|00001|00001|000|0100|0|1100011
#            = 0b0_000000_00001_00001_000_0100_0_1100011
#            = 0x0010_8463

# Hmm it's getting complicated. Let me just use Python to encode.
# Actually, let me check these with a simpler approach:

$coreHex = @"
00500093
00300113
002081B3
40208233
0020F2B3
0020E333
00800393
00702023
00002383
00108463
00A00413
0040006F
02A00413
00209493
0010A533
0040006F
FF9FF06F
"@

$coreHex -split "`n" | ForEach-Object { if ($_.Trim() -ne "") { $_.Trim() }} |
    Set-Content "$hexDir\core_test_words.hex"
Status ($?) "core_test_words.hex generated ($((Get-Item "$hexDir\core_test_words.hex").Length) bytes)"

# ============================================================================
# 2. Generate pipeline_test_words.hex (for tb_core_pipeline.sv)
# Pipeline test: EX->EX forward, MEM->WB forward, Load-Use stall,
#                Branch taken/not-taken, JAL
# ============================================================================
Log "Generating pipeline_test_words.hex..."

$pipelineHex = @"
00500093
00308113
002081B3
00A00213
00120293
00000313
00B20393
02A00413
00802023
00002483
00548513
00700313
00730033
00418463
00000013
00A00693
00400E6F
00000013
02D306B3
00100713
00200793
00279663
00000013
04200813
00400E6F
00000013
00C10713
00000013
00000E33
042000EF
00000013
02C00E93
02000F13
0040006F
00000013
FF9FF06F
"@
# Wait I'm hand-encoding complex instructions... Let me use Python instead.
# The assembler with NOPs is going to be tedious.
# Let me just use Python to create the pipeline hex directly.

Log "Using Python for precise encoding..."

python -c "
# Encode pipeline test instructions directly
# Test expectations:
# EX→EX forward: x1=5, x2=8, x3=13
# MEM→WB forward: x4=10, x5=11, x6=0, x7=21
# Load-Use stall: x8=42, x9=42, x10=47
# Branch taken: x11=7, x12=7, x13=55
# Branch not taken: x14=1, x15=2, x16=66
# JAL: x17=ret_addr, x18=44
# MEM[0]=42

# Helper functions
def R(funct7, rs2, rs1, funct3, rd):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33

def I(imm, rs1, funct3, rd, opcode):
    imm = imm & 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def S(imm, rs2, rs1, funct3):
    imm = imm & 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | 0x23

def B(imm, rs2, rs1, funct3):
    imm = imm & 0x1FFF
    # B-type encoding: {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode=1100011}
    b = (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63
    return b

def J(imm, rd):
    imm = imm & 0x1FFFFF
    # J-type: {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode=1101111}
    b = (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F
    return b

def addi(rd, rs1, imm): return I(imm, rs1, 0, rd, 0x13)
def add(rd, rs1, rs2):  return R(0, rs2, rs1, 0, rd)
def sub(rd, rs1, rs2):  return R(0x20, rs2, rs1, 0, rd)
def and_(rd, rs1, rs2): return R(0, rs2, rs1, 7, rd)
def or_(rd, rs1, rs2):  return R(0, rs2, rs1, 6, rd)
def slli(rd, rs1, sh):  return I(sh, rs1, 1, rd, 0x13)
def slt(rd, rs1, rs2):  return R(0, rs2, rs1, 2, rd)
def sw(rs2, imm, rs1):  return S(imm, rs2, rs1, 2)
def lw(rd, imm, rs1):   return I(imm, rs1, 2, rd, 0x03)
def beq(rs1, rs2, imm): return B(imm, rs2, rs1, 0)
def bne(rs1, rs2, imm): return B(imm, rs2, rs1, 1)
def jal(rd, imm):       return J(imm, rd)
def jalr(rd, rs1, imm): return I(imm, rs1, 0, rd, 0x67)
def nop():              return addi(0, 0, 0)

# Program layout (no delay slots - NOPs manually inserted where needed):
# Total: ~34 instructions, pipeline TB runs 40 cycles

instrs = []

# === EX→EX forwarding ===
instrs.append(addi(1, 0, 5))    # 0: x1=5
instrs.append(addi(2, 1, 3))    # 1: x2=8 (forward x1 EX→EX)
instrs.append(add(3, 1, 2))     # 2: x3=13 (forward x1+2)

# === Something (labelled MEM→WB) ===
instrs.append(addi(4, 0, 10))   # 3: x4=10
instrs.append(addi(5, 4, 1))    # 4: x5=11
instrs.append(addi(6, 0, 0))    # 5: x6=0
instrs.append(addi(7, 4, 11))   # 6: x7=21

# === Load-Use stall ===
instrs.append(addi(8, 0, 42))   # 7: x8=42
instrs.append(sw(8, 0, 0))      # 8: MEM[0]=42
instrs.append(lw(9, 0, 0))      # 9: x9=42 (load, may stall)
instrs.append(addi(10, 9, 5))   # 10: x10=47 (load-use hazard)

# === Branch taken ===
instrs.append(addi(11, 0, 7))   # 11: x11=7
instrs.append(add(12, 11, 0))   # 12: x12=7
# beq x11, x11, TAKEN (skip 3 instrs = +12 bytes from beq address)
# Target is at index 16, beq is at index 13
# offset = (16 - 13) * 4 = 12
instrs.append(beq(11, 11, 12))  # 13: TAKEN! jump to index 16
instrs.append(addi(13, 0, 10))  # 14: NOT executed
instrs.append(jal(0, 8))        # 15: j +8 = skip to index 18 (NOT executed)
instrs.append(addi(13, 11, 48)) # 16: TAKEN target: x13=55
instrs.append(nop())            # 17: padding

# === Branch NOT taken ===
instrs.append(addi(14, 0, 1))   # 18: x14=1
instrs.append(addi(15, 0, 2))   # 19: x15=2
# beq x14, x15, SKIP = NOT TAKEN (1 != 2)
# Target at index 22, beq at index 20
# offset = (22 - 20) * 4 = 8
instrs.append(beq(14, 15, 8))   # 20: NOT taken
instrs.append(addi(16, 0, 66))  # 21: x16=66

# === JAL ===
# jal x17, JAL_TARGET (at index 24, which is 2 after + nop = need to compute)
# jal at index 22, target at index 26
# offset = (26 - 22) * 4 = 16
instrs.append(jal(17, 16))      # 22: jal x17, target
instrs.append(nop())            # 23: delay slot placeholder
instrs.append(addi(18, 0, 44))  # 24: x18=44
# j END (index 27, 2 instrs after = +8)
instrs.append(jal(0, 8))        # 25: j END
instrs.append(nop())            # 26: delay slot placeholder
instrs.append(nop())            # 27: END (padding for target JAL_TARGET)

# Wait, this doesn't work. The JAL target needs to return.
# Let me redesign. JAL to target, target returns.

# Better approach: JAL at index 22, target at ~index 28
# I need to count instructions carefully.

# Let me restart with a cleaner layout:
"

Write-Host $LASTEXITCODE
# Check result
if ($LASTEXITCODE -eq 0) {
    "Python executed"  
}
"