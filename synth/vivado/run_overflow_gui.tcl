# ============================================================================
# run_overflow_gui.tcl - Overflow Test Bitstream Generation
# ============================================================================
# Run this in Vivado GUI Tcl Console:
#   source d:/cache-riscv-cpu-design/synth/vivado/run_overflow_gui.tcl
#
# Steps:
#   1. Refresh firmware.hex (1449 instrs, 2.83x cache capacity)
#   2. Synthesize (synth_1)
#   3. Implement + bitstream (impl_1)
#   4. Report bit file path
#
# Estimated time: synth ~5min, impl ~10min, total ~15min
# ============================================================================

puts "=============================================="
puts " Overflow Test Bitstream Generation"
puts "=============================================="
puts ""

# Step 1: Confirm project is open
set cur_proj [current_project]
puts "Current project: $cur_proj"

# Step 2: Check firmware.hex
set fw_file [get_files "firmware.hex"]
if {$fw_file != ""} {
    puts "firmware.hex path: $fw_file"
} else {
    puts "WARNING: firmware.hex not found in project"
}

puts ""
puts ">>> Step 1/3: Starting Synthesis (synth_1)..."
puts ">>> Estimated time: ~5 minutes"

# Step 3: Reset and run synthesis
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts ">>> Synth status: $synth_status"

if {$synth_status != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed! Check synth log."
    return -code error "Synthesis failed"
}
puts ">>> Synthesis complete!"
puts ""

# Step 4: Run implementation + bitstream
puts ">>> Step 2/3: Starting Implementation (impl_1, with bitstream)..."
puts ">>> Estimated time: ~10 minutes"

reset_run impl_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts ">>> Impl status: $impl_status"
puts ">>> Implementation complete!"
puts ""

# Step 5: Check bit file
puts ">>> Step 3/3: Checking Bitstream..."
set proj_dir [get_property DIRECTORY [current_project]]
set bit_file [file join $proj_dir "rvp_nexys4.runs" "impl_1" "rvp_fpga_top.bit"]

if {[file exists $bit_file]} {
    set bit_size [file size $bit_file]
    set bit_time [file mtime $bit_file]
    puts ""
    puts "=============================================="
    puts " SUCCESS! Bitstream generated"
    puts "=============================================="
    puts "File: $bit_file"
    puts "Size: $bit_size bytes"
    puts "Time: [clock format $bit_time -format "%Y-%m-%d %H:%M:%S"]"
    puts ""
    puts "Next steps:"
    puts "  1. Open Hardware Manager"
    puts "  2. Connect Nexys4 DDR board"
    puts "  3. Program FPGA"
    puts "  4. Watch UART output (115200 baud)"
    puts "=============================================="
} else {
    puts "ERROR: Bitstream file not found!"
    puts "Expected path: $bit_file"
    puts "Check implementation log for errors."
}
