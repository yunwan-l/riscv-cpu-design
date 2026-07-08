#!/usr/bin/env python3
"""Fix SoC TB: increase cycle count, verify hex loading."""

path = "E:/rvp_nexys/tb/tb_soc.sv"

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# Change 50 cycles to 200
old = "repeat (50) @(posedge clk);"
new = "repeat (200) @(posedge clk);  // increased for SoC bus latency"

if old in content:
    content = content.replace(old, new)
    print("Increased cycles: 50 -> 200")
else:
    print(f"Pattern not found! Searching for 'repeat' lines...")
    for i, line in enumerate(content.split("\n")):
        if "repeat" in line and "posedge" in line:
            print(f"  Line {i}: {line}")

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

# Also verify HEX file exists and has content
import os
hex_path = "E:/rvp_nexys/sw/tests/soc_test_words.hex"
if os.path.exists(hex_path):
    with open(hex_path) as f:
        lines = [l.strip() for l in f if l.strip()]
    print(f"HEX file: {len(lines)} words, first={lines[0]}, last={lines[-1]}")
else:
    print("HEX file NOT FOUND!")

print("Done.")
