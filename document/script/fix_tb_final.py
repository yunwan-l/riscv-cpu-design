#!/usr/bin/env python3
"""Final fix for testbench $readmemh calls."""

import re
import os

TB_DIR = "E:/rvp_nexys/tb"
SW_TESTS = "E:/rvp_nexys/sw/tests"

# The correct readmemh for each TB
fixes = {
    "tb_core_single.sv": {
        "old_comment": None,  # don't search by old text, just add #1
        "hex": "core_test_words.hex",
        "mem": "dut.instr_mem.mem",
    },
    "tb_core_pipeline.sv": {
        "hex": "pipeline_test_words.hex",
        "mem": "dut.instr_mem.mem",
    },
    "tb_soc.sv": {
        "hex": "soc_test_words.hex",
        "mem": "dut.cpu.instr_mem.mem",
    },
    "tb_rv32ui_p_all.sv": {
        "hex": "rv32ui_p_all_words.hex",
        "mem": "dut.instr_mem.mem",
    },
}

for tb_name, cfg in fixes.items():
    tb_path = os.path.join(TB_DIR, tb_name)
    hex_path = os.path.join(SW_TESTS, cfg["hex"])
    
    with open(tb_path, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Find and replace any $readmemh call with the correct one
    # Pattern: $readmemh(...);
    readmemh_pattern = r'\$readmemh\s*\([^;]+\);'
    
    # Find the FIRST occurrence
    def replace_readmemh(match):
        full = match.group(0)
        new_readmemh = '    $readmemh("' + hex_path.replace("\\", "/") + '", ' + cfg["mem"] + ');'
        print(f"  {tb_name}: replacing {full[:50]}...")
        return new_readmemh
    
    new_content, count = re.subn(readmemh_pattern, replace_readmemh, content, count=1, flags=re.DOTALL)
    
    if count > 0:
        # Check if #1 is already before $readmemh
        has_delay = False
        for pattern in ["#1;", "#1 //", "#1  //"]:
            if pattern in new_content:
                idx_delay = max(new_content.rfind(pattern, 0, new_content.find("$readmemh")), 0)
                idx_readmemh = new_content.find("$readmemh")
                if idx_delay > 0 and idx_readmemh - idx_delay < 80:
                    has_delay = True
        
        if not has_delay:
            # Add #1 before the $readmemh
            new_content = new_content.replace(
                '    $readmemh("' + hex_path.replace("\\", "/") + '", ' + cfg["mem"] + ');',
                '    #1;  // wait for memory init\n    $readmemh("' + hex_path.replace("\\", "/") + '", ' + cfg["mem"] + ');'
            )
        
        with open(tb_path, "w", encoding="utf-8") as f:
            f.write(new_content)
        print(f"  {tb_name}: fixed OK")
    else:
        print(f"  {tb_name}: no $readmemh found!")
        # Check what's in the file
        for i, line in enumerate(content.split("\n")):
            if "readmem" in line.lower():
                print(f"    Line {i}: {line.strip()[:80]}")

print("\nDone.")
