#!/usr/bin/env python3
"""Debug the full_test assembly - find the problematic line."""
import sys, re
sys.path.insert(0, r'E:\rvp_nexys\sw\tests')

asm_text = open(r'E:\rvp_nexys\document\script\gen_full_test.py').read()
m = re.search(r'FULL_TEST_ASM = """"(.*?)""""', asm_text, re.DOTALL)
if not m:
    m = re.search(r'FULL_TEST_ASM = """(.*?)"""', asm_text, re.DOTALL)
if m:
    src = m.group(1)
    from rv_assembler import Assembler
    asm = Assembler()
    lines = [l for l in src.split('\n')]
    try:
        hex_words = asm.assemble(lines)
        print(f"OK: {len(hex_words)} instructions")
    except ValueError as e:
        print(f"ERROR: {e}")
        # Find what line caused it
        # Re-process line by line
        asm2 = Assembler()
        src_lines = list(asm2._preprocess(lines))
        for i, l in enumerate(src_lines):
            stripped = l.split('#')[0].strip()
            if not stripped:
                continue
            if stripped in asm2.labels:
                continue
            # Try to identify if it contains control flow (has pseudo/branch)
            if ':' in stripped:
                stripped = stripped.split(':', 1)[1].strip()
            try:
                asm2._encode_line(stripped, i)
            except ValueError as ve:
                print(f"  Line {i}: '{l}' -> '{stripped}' -> {ve}")
else:
    print("Could not find pattern")
