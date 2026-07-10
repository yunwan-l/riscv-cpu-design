# =============================================================================
# build_counter.tcl - Build CPU Auto-Increment Counter Firmware
# =============================================================================
# This script does EVERYTHING in one step:
#   1. Copies the counter firmware to all locations
#   2. Forces Vivado to re-read the firmware file (removes stale cache)
#   3. Resets and re-runs synthesis + implementation + bitstream
#
# Usage in Vivado Tcl Console:
#   source C:/rvp_proj/synth/vivado/build_counter.tcl
#
# Usage in batch mode (from command line):
#   vivado -mode batch -source C:/rvp_proj/synth/vivado/build_counter.tcl
#
# All paths use ASCII-only C:/rvp_proj/ (NO Chinese characters).
# =============================================================================

set script_dir  "C:/rvp_proj/synth/vivado"
set proj_root   "C:/rvp_proj"
set xpr_file    "C:/rvp_proj/build/vivado/rvp_nexys4.xpr"
set fw_src      "C:/rvp_proj/synth/vivado/firmware_counter.hex"
set imports_fw  "C:/rvp_proj/build/vivado/rvp_nexys4.srcs/sources_1/imports/firmware.hex"
set root_fw     "C:/rvp_proj/firmware.hex"
set synth_fw    "C:/rvp_proj/synth/vivado/firmware.hex"

puts "============================================================================="
puts " CPU Auto-Increment Counter - Full Rebuild"
puts "============================================================================="
puts " Script dir : $script_dir"
puts " Project    : $xpr_file"
puts " Firmware   : $fw_src"
puts "============================================================================="

# --- Step 1: Verify the counter firmware exists ---
if {![file exists $fw_src]} {
    puts "ERROR: Counter firmware not found: $fw_src"
    puts "Please run the firmware generator first:"
    puts "  python C:/rvp_proj/sw/tests/rv_assembler.py"
    return
}

# --- Step 2: Copy firmware_counter.hex to ALL firmware.hex locations ---
puts ""
puts "--- Copying counter firmware to all locations ---"

file copy -force $fw_src $synth_fw
puts "\[OK\] $synth_fw"

file copy -force $fw_src $root_fw
puts "\[OK\] $root_fw"

# Create imports directory if needed and copy
set imports_dir [file dirname $imports_fw]
file mkdir $imports_dir
file copy -force $fw_src $imports_fw
puts "\[OK\] $imports_fw (Vivado project imports)"

# --- Step 3: Open the project ---
puts ""
puts "--- Opening project ---"

set proj_open 0
if {[catch {current_project} proj] == 0 && $proj ne ""} {
    set proj_open 1
    puts "Project already open: $proj"
}

if {!$proj_open} {
    if {[file exists $xpr_file]} {
        puts "Opening: $xpr_file"
        open_project $xpr_file
    } else {
        puts "ERROR: Project not found: $xpr_file"
        puts "Please create the project first using create_project.tcl"
        return
    }
}

# --- Step 4: Force Vivado to re-read the firmware ---
# This is the CRITICAL step that fixes "always burns script 1".
# When firmware.hex is imported, Vivado caches its content.
# We must force it to re-read by toggling is_enabled.
puts ""
puts "--- Forcing firmware re-read (clearing stale cache) ---"

set fw_files [get_files firmware.hex]
if {[llength $fw_files] > 0} {
    # Method 1: Toggle is_enabled
    set_property is_enabled false [lindex $fw_files 0]
    set_property is_enabled true  [lindex $fw_files 0]
    puts "\[OK\] Toggled is_enabled on firmware.hex"

    # Method 2: Also touch the file timestamp to ensure Vivado sees a change
    set fw_path [get_property PATH [lindex $fw_files 0]]
    puts "  Tracked firmware path: $fw_path"
} else {
    puts "WARNING: firmware.hex not found in project sources."
    puts "  Adding it now..."
    add_files -norecurse $synth_fw
    puts "\[OK\] Added firmware.hex to project"
}

# Update compile order to reflect changes
update_compile_order -fileset sources_1
puts "\[OK\] Compile order updated"

# --- Step 5: Reset and re-run synthesis ---
puts ""
puts "============================================================================="
puts " Resetting synth_1..."
puts "============================================================================="
reset_run synth_1

puts "Running Synthesis... (this takes 2-5 minutes)"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed! Check the log:"
    puts "  C:/rvp_proj/build/vivado/rvp_nexys4.runs/synth_1/rvp_fpga_top.log"
    return
}

# --- Step 6: Reset and re-run implementation ---
puts ""
puts "============================================================================="
puts " Resetting impl_1..."
puts "============================================================================="
reset_run impl_1

puts "Running Implementation... (this takes 2-5 minutes)"
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"

if {$impl_status ne "route_design Complete!"} {
    puts "ERROR: Implementation failed! Check the log:"
    puts "  C:/rvp_proj/build/vivado/rvp_nexys4.runs/impl_1/rvp_fpga_top.log"
    return
}

# --- Step 7: Generate bitstream ---
puts ""
puts "============================================================================="
puts " Generating Bitstream..."
puts "============================================================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bs_status [get_property STATUS [get_runs impl_1]]
puts "Bitstream status: $bs_status"

# --- Step 8: Find and report the bitstream ---
set bitfile [glob -nocomplain "C:/rvp_proj/build/vivado/rvp_nexys4.runs/impl_1/*.bit"]
if {[llength $bitfile] > 0} {
    # Also copy to the convenient location
    file copy -force [lindex $bitfile 0] "C:/rvp_proj/build/vivado/rvp_nexys4.bit"
    puts ""
    puts "============================================================================="
    puts " SUCCESS! CPU Auto-Increment Counter firmware built."
    puts "============================================================================="
    puts " Bitstream: [lindex $bitfile 0]"
    puts " Also at:   C:/rvp_proj/build/vivado/rvp_nexys4.bit"
    puts ""
    puts " Next steps in Vivado:"
    puts "   1. Open Hardware Manager"
    puts "   2. Open Target -> Auto Connect"
    puts "   3. Right-click xc7a100t -> Program Device"
    puts "   4. Select the .bit file above"
    puts ""
    puts " Expected result on board:"
    puts "   - 16 LEDs show an incrementing binary counter (0,1,2,3,...)"
    puts "   - Each count takes ~0.5 seconds"
    puts "   - 7-segment display shows the PC value (looping in the program)"
    puts "============================================================================="
} else {
    puts "WARNING: Bitstream file not found. Check impl_1 results."
    puts "  C:/rvp_proj/build/vivado/rvp_nexys4.runs/impl_1/"
}
