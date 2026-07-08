#!/usr/bin/env python3
"""Fix testbenches to use $readmemh (with #1 delay) instead of direct assignments."""

import re
import os

TB_DIR = "E:/rvp_nexys/tb"
SW_TESTS = "E:/rvp_nexys/sw/tests"

tbs = {
    "tb_core_single.sv": ("core_test_words.hex", "dut.instr_mem.mem"),
    "tb_core_pipeline.sv": ("pipeline_test_words.hex", "dut.instr_mem.mem"),
    "tb_rv32ui_p_all.sv": ("rv32ui_p_all_words.hex", "dut.instr_mem.mem"),
    "tb_soc.sv": ("soc_test_words.hex", "dut.cpu.instr_mem.mem"),
}

for tb_name, (hex_name, mem_path) in tbs.items():
    tb_path = os.path.join(TB_DIR, tb_name)
    
    with open(tb_path, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Remove all "mem[N] = 32'h..." lines
    lines = content.split("\n")
    new_lines = []
    in_assign_block = False
    assign_count = 0
    
    for line in lines:
        stripped = line.strip()
        is_assign = bool(re.match(r'.*mem\[\d+\]\s*=\s*32.*;', stripped))
        
        if is_assign:
            if not in_assign_block:
                in_assign_block = True
            assign_count += 1
        else:
            if in_assign_block:
                # End of assignment block - insert $readmemh
                hex_path = os.path.join(SW_TESTS, hex_name).replace("\\", "/")
                new_lines.append("    #1;  // wait for mem init")
                new_lines.append("    $readmemh(\"" + hex_path + "\", " + mem_path + ");")
                in_assign_block = False
            new_lines.append(line)
    
    # Handle case where assignments go to end of file
    if in_assign_block:
        hex_path = os.path.join(SW_TESTS, hex_name).replace("\\", "/")
        new_lines.append("    #1;  // wait for mem init")
        new_lines.append("    $readmemh(\"" + hex_path + "\", " + mem_path + ");")
    
    content_new = "\n".join(new_lines)
    
    # Also remove any misplaced "// wait for mem init" comments
    content_new = re.sub(r'#1\s*// wait for mem init\s*\n', '', content_new)
    
    # Write back
    with open(tb_path, "w", encoding="utf-8") as f:
        f.write(content_new)
    
    if assign_count > 0:
        print(f"{tb_name}: replaced {assign_count} assignments -> $readmemh({hex_name})")
    else:
        print(f"{tb_name}: no assignments found")

print("\nDone.")
