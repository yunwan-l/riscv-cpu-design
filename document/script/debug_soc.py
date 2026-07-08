#!/usr/bin/env python3
"""Add debug output to SoC TB to trace PC and instruction."""

path = "E:/rvp_nexys/tb/tb_soc.sv"

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# Add debug after $readmemh and before reset
# Find the first 'initial begin' 
insert_point = content.find("#1;  // wait for memory init")
if insert_point >= 0:
    # Find the line end
    next_nl = content.find("\n", insert_point)
    
    debug_blk = '''
    // Debug: dump first 4 memory words
    $display("=== SoC IMEM Debug ===");
    $display("IMEM[0] = %h (exp lui x5=000102b7)", dut.cpu.instr_mem.mem[0]);
    $display("IMEM[1] = %h (exp addi t1=00000234)", dut.cpu.instr_mem.mem[1]);
    $display("IMEM[2] = %h (exp lui t2=00001002)", dut.cpu.instr_mem.mem[2]);

''' 
    
    content = content[:next_nl+1] + debug_blk + content[next_nl+1:]
    
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    
    print("Debug added")
else:
    print("Cannot find insertion point")
    for i, line in enumerate(content.split("\n")):
        if "readmemh" in line or "wait for" in line:
            print(f"  Line {i}: {line}")
