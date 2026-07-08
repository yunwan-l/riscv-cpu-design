#!/usr/bin/env python3
"""Fix pipeline TB cycle count and SoC TB hex loading."""

import re

TB_DIR = "E:/rvp_nexys/tb"
PIPELINE_TB = f"{TB_DIR}/tb_core_pipeline.sv"
SOC_TB = f"{TB_DIR}/tb_soc.sv"
SOC_HEX = "E:/rvp_nexys/sw/tests/soc_test_words.hex"

def fix_pipeline_tb():
    """Increase cycle count in pipeline TB and fix JAL test."""
    with open(PIPELINE_TB, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Increase cycle count from 40 to 60
    old = "repeat (40) @(posedge clk);"
    new = "repeat (60) @(posedge clk);"
    if old in content:
        content = content.replace(old, new)
        print("  Increased cycles: 40 -> 60")
    
    with open(PIPELINE_TB, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  Fixed: {PIPELINE_TB}")


def fix_soc_tb():
    """Replace $readmemh with direct assignments in SoC TB (bypass race condition)."""
    with open(SOC_TB, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Check if $readmemh exists
    if '$readmemh' not in content:
        print("  No $readmemh found in SOC TB")
        return
    
    # Read the hex file
    with open(SOC_HEX) as f:
        hex_words = [line.strip() for line in f if line.strip()]
    
    print(f"  Read {len(hex_words)} hex words for SOC")
    
    # Generate direct assignments
    assigns = "    // Direct instruction memory initialization\n"
    for i, h in enumerate(hex_words):
        assigns += f"    dut.instr_mem_inst.mem[{i}] = 32'h{h};\n"
    
    # Find and replace $readmemh
    # Match: $readmemh("path", mem_path);
    import re as re_mod
    match = list(re_mod.finditer(r'\$readmemh\s*\([^;]+\);', content))
    
    if match:
        for m in match:
            full = m.group(0)
            # The second argument is the mem array
            parts = full.split(',')
            if len(parts) >= 2:
                mem_path = parts[1].strip().rstrip(';). ')
            else:
                mem_path = "dut.cpu.instr_mem.mem"
            # Fix: the SoC hierarchy uses dut.cpu.instr_mem not dut.instr_mem_inst
            if 'instr_mem_inst' in mem_path:
                mem_path = mem_path.replace('instr_mem_inst', 'cpu.instr_mem')
            print(f"  Replacing: {full[:50]}... -> {mem_path}")
            content = content.replace(full, assigns)
    else:
        # Fallback: try to find by string
        old_patterns = [
            '$readmemh("../sw/tests/soc_test_words.hex",',
            '$readmemh("E:/rvp_nexys/sw/tests/soc_test_words.hex",'
        ]
        for pat in old_patterns:
            if pat in content:
                # Find the end of this statement
                start = content.find(pat)
                end = content.find(');', start)
                if end > 0:
                    old_stmt = content[start:end+2]
                    print(f"  Replacing (fallback): {old_stmt[:50]}...")
                    content = content.replace(old_stmt, assigns)
    
    with open(SOC_TB, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  Fixed: {SOC_TB}")


fix_pipeline_tb()
fix_soc_tb()
print("\nDone.")
