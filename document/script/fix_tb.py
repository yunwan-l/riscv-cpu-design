#!/usr/bin/env python3
"""Fix testbench to use direct memory initialization instead of $readmemh."""

import os
import sys

TB_DIR = "E:/rvp_nexys/tb"
SW_TESTS = "E:/rvp_nexys/sw/tests"

# Hex file paths
hex_files = {
    "tb_core_single.sv": "core_test_words.hex",
    "tb_core_pipeline.sv": "pipeline_test_words.hex",
    "tb_rv32ui_p_all.sv": "rv32ui_p_all_words.hex",
    "tb_soc.sv": "soc_test_words.hex",
}

def hex_to_initial_assign(hex_path, mem_path):
    """Convert hex file to SystemVerilog direct assignments."""
    with open(hex_path) as f:
        words = [line.strip() for line in f if line.strip()]
    
    lines = []
    lines.append("    #1;  // wait for clock + instr_mem init")
    for i, h in enumerate(words):
        lines.append(f"    {mem_path}[{i}] = 32'h{h};")
    
    return "\n".join(lines)


def fix_testbench(tb_name, hex_name):
    """Replace $readmemh with direct assignments in a testbench file."""
    tb_path = os.path.join(TB_DIR, tb_name)
    hex_path = os.path.join(SW_TESTS, hex_name)
    
    if not os.path.exists(tb_path):
        print(f"ERROR: {tb_path} not found")
        return False
    
    with open(tb_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    # Find the $readmemh call
    # Pattern: either "$readmemh(" or "$readmemh ("
    import re
    
    # Find all $readmemh calls
    matches = list(re.finditer(r'\$readmemh\s*\([^;]+\);', content))
    if not matches:
        print(f"No $readmemh found in {tb_name}")
        return False
    
    for m in matches:
        full_match = m.group(0)
        # Determine the mem array path from the call
        # Pattern: $readmemh("path", mem_path);
        parts = full_match.split(',')
        if len(parts) >= 2:
            mem_path = parts[1].strip().rstrip(');)')
        else:
            mem_path = "dut.instr_mem.mem"
        
        print(f"  Replacing: {full_match[:60]}...  -> mem_path={mem_path}")
        
        # Generate replacement
        assign_code = hex_to_initial_assign(hex_path, mem_path)
        
        # Replace in content
        content = content.replace(full_match, assign_code)
    
    # Also remove the #1 that might be before readmemh  
    # Find and remove any "// wait for mem init" lines
    content = re.sub(r'\s*#1\s*// wait for mem init\s*\n?', '\n', content)
    
    with open(tb_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"OK: {tb_name} fixed")
    return True


def main():
    for tb, hex_name in hex_files.items():
        hex_path = os.path.join(SW_TESTS, hex_name)
        if not os.path.exists(hex_path):
            print(f"WARNING: {hex_path} not found, skipping {tb}")
            continue
        fix_testbench(tb, hex_name)
    
    print("\nDone.")


if __name__ == "__main__":
    main()
