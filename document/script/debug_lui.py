"""Debug LUI encoding bug."""
import sys
sys.path.insert(0, r'E:\rvp_nexys\sw\tests')
from rv_assembler import Assembler, REG_NAMES, enc_u_type

# Test: what does the assembler generate for 'lui t0, 0x10010'?
asm = Assembler()
lines = ['lui t0, 0x10010']
result = asm.assemble(lines)
for r in result:
    print(f'Result: 0x{r}')

# Manual decode
val = int(result[0], 16)
opcode = val & 0x7F
rd = (val >> 7) & 0x1F
imm20 = (val >> 12) & 0xFFFFF
print(f'Decoded: opcode=0x{opcode:02x} rd=x{rd} imm20=0x{imm20:05x}')
print(f'  -> lui x{rd}, 0x{imm20:x} -> x{rd}=0x{imm20<<12:08x}')
print(f'Expected: lui x5(t0), 0x10010 -> x5 = 0x10010000')

# Direct enc_u_type test
v0 = enc_u_type(0x10010, 5, 0x37)
print(f'\nenc_u_type(0x10010, x5, 0x37) = 0x{v0:08x}')

v1 = enc_u_type(0x10010000, 5, 0x37)
print(f'enc_u_type(0x10010000, x5, 0x37) = 0x{v1:08x}')

# Test what the full soc_test program generates
test_lines = """
lui t0, 0x10010
addi t1, x0, 0x234
lui t2, 0x00001
add t1, t1, t2
sw t1, 0(t0)
lw t2, 4(t0)
""".strip().split('\n')

result2 = asm.assemble(test_lines)
print(f'\nFull test ({len(result2)} instructions):')
for i, r in enumerate(result2):
    val = int(r, 16)
    opcode = val & 0x7F
    rd = (val >> 7) & 0x1F
    imm20 = (val >> 12) & 0xFFFFF
    rs1 = (val >> 15) & 0x1F
    rs2 = (val >> 20) & 0x1F
    print(f'  [{i}] 0x{r}: op=0x{opcode:02x} rd=x{rd} rs1=x{rs1} rs2=x{rs2} imm=0x{imm20:05x}')
