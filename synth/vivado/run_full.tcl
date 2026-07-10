open_project build/vivado/rvp_nexys4.xpr

# Add synth/vivado to include dirs so $readmemh can find firmware.hex
set inc_dirs [get_property include_dirs [get_filesets sources_1]]
lappend inc_dirs [file normalize synth/vivado]
set_property include_dirs $inc_dirs [get_filesets sources_1]
puts "Include dirs: [get_property include_dirs [get_filesets sources_1]]"

# Also copy firmware.hex to the source file's directory as fallback
file copy -force [file join synth vivado firmware.hex] [file join rtl core firmware.hex]

# Run synthesis
puts "=== Starting Synthesis ==="
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check if checkpoint exists
set dcp [glob -nocomplain build/vivado/rvp_nexys4.runs/synth_1/*.dcp]
if {$dcp eq ""} {
    puts "ERROR: No synthesis checkpoint found"
    exit 1
}
puts "Synthesis checkpoint: $dcp"

# Run implementation
puts "=== Starting Implementation ==="
reset_run impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Generate bitstream
puts "=== Generating Bitstream ==="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Check for bitstream
set bitfile [file join build vivado rvp_nexys4.runs impl_1 rvp_fpga_top.bit]
if {[file exists $bitfile]} {
    puts "BITSTREAM_OK: size=[file size $bitfile]"
} else {
    puts "BITSTREAM_MISSING"
}

# Clean up firmware.hex copy from rtl/core
file delete -force [file join rtl core firmware.hex]

exit