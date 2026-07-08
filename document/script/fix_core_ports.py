#!/usr/bin/env python3
"""Fix core files: byte address -> word address for instruction/ data memory."""

import re

SINGLE = "E:/rvp_nexys/rtl/core/rvp_core_single.sv"
PIPELINE = "E:/rvp_nexys/rtl/core/rvp_core_pipeline.sv"

def fix_instr_mem_port(content):
    """Replace incorrect addr_i(pc) with addr_i(pc[12:2])."""
    # Look for: .addr_i  (pc),
    content = re.sub(
        r'\.addr_i\s*\(pc\s*\)',
        '.addr_i  (pc[12:2])',
        content
    )
    content = re.sub(
        r'\.addr_i\s*\(alu_result\s*\)',
        '.addr_i  (alu_result[12:0])',
        content
    )
    return content

for path in [SINGLE, PIPELINE]:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    new_content = fix_instr_mem_port(content)
    
    if new_content != content:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Fixed: {path}")
    else:
        # Check what the file has
        for line in content.split('\n'):
            if 'addr_i' in line and 'pc' in line:
                print(f"  Found: {line.strip()}")
            if 'addr_i' in line and 'alu' in line:
                print(f"  Found: {line.strip()}")
        print(f"NO CHANGE: {path}")
