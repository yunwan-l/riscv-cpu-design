# =============================================================================
# switch_firmware.tcl - RVP Firmware Switcher (run inside Vivado Tcl Console)
# =============================================================================
# Usage:
#   set fw_choice 2
#   source C:/rvp_proj/synth/vivado/switch_firmware.tcl
#
# Or directly:
#   source C:/rvp_proj/synth/vivado/switch_firmware.tcl
#   (it will prompt you in the Tcl console)
# =============================================================================

# --- Firmware list ---
set fw_list [list \
    [list "firmware_blink.hex"    "LED Blink (original)"] \
    [list "firmware_pc_seq.hex"   "PC Sequential"] \
    [list "firmware_forward.hex"  "Forwarding"] \
    [list "firmware_loaduse.hex"  "Load-Use"] \
    [list "firmware_branch.hex"   "Branch"] \
    [list "firmware_alu.hex"      "ALU"] \
    [list "firmware_mem.hex"      "Memory"] \
    [list "firmware_muldiv.hex"   "MUL/DIV"] \
    [list "firmware_pipeline.hex" "Pipeline Demo"] \
    [list "firmware_counter.hex"  "CPU Counter"] \
    [list "firmware_piano.hex"    "Piano (UART note data)"] \
)]

# --- Determine script directory ---
set script_dir "C:/rvp_proj/synth/vivado"

puts "============================================================================="
puts " RVP Firmware Switcher"
puts "============================================================================="
puts " Script dir: $script_dir"
puts ""

# --- Show menu ---
puts "Available firmware:"
for {set i 0} {$i < [llength $fw_list]} {incr i} {
    set num [expr {$i + 1}]
    set fname [lindex $fw_list $i 0]
    set fdesc [lindex $fw_list $i 1]
    puts [format "   \[%d\] %-25s %s" $num $fname $fdesc]
}
puts ""

# --- Get user choice ---
if {![info exists fw_choice]} {
    puts -nonewline "Enter firmware number (1-11): "
    flush stdout
    set fw_choice [gets stdin]
}

set idx [expr {$fw_choice - 1}]
if {$idx < 0 || $idx >= [llength $fw_list]} {
    puts "ERROR: Invalid choice '$fw_choice'"
    return
}

set fw_file [lindex $fw_list $idx 0]
set fw_name [lindex $fw_list $idx 1]
set fw_src [file join $script_dir $fw_file]

puts "Selected: $fw_name"
puts "Source:   $fw_src"

if {![file exists $fw_src]} {
    puts "ERROR: File not found: $fw_src"
    return
}

# --- Copy firmware.hex to ALL locations ---
set fw_dst_main [file join $script_dir "firmware.hex"]
file copy -force $fw_src $fw_dst_main
puts "\[OK\] $fw_dst_main"

set proj_internal "C:/rvp_proj/build/vivado/rvp_nexys4.srcs/sources_1/imports/firmware.hex"
if {[file exists [file dirname $proj_internal]]} {
    file copy -force $fw_src $proj_internal
    puts "\[OK\] $proj_internal"
}

set proj_root "C:/rvp_proj/firmware.hex"
file copy -force $fw_src $proj_root
puts "\[OK\] $proj_root"

puts ""
puts "============================================================================="
puts " Firmware replaced. Now rebuilding..."
puts "============================================================================="

# --- Check if project is open ---
set proj_open 0
if {[catch {current_project} proj] == 0 && $proj ne ""} {
    set proj_open 1
    puts "Current project: $proj"
}

if {!$proj_open} {
    set xpr_file "C:/rvp_proj/build/vivado/rvp_nexys4.xpr"
    if {[file exists $xpr_file]} {
        puts "Opening project: $xpr_file"
        open_project $xpr_file
    } else {
        puts "ERROR: No project open and cannot find $xpr_file"
        puts "Please open your Vivado project first, then re-run this script."
        return
    }
}

# --- Update firmware.hex in the project's file list ---
set fw_files [get_files firmware.hex]
if {[llength $fw_files] > 0} {
    set_property is_enabled false [lindex $fw_files 0]
    set_property is_enabled true  [lindex $fw_files 0]
    puts "Updated firmware.hex reference in project"
}

# --- Reset synthesis run ---
puts ""
puts "Resetting synth_1..."
reset_run synth_1

# --- Run synthesis ---
puts ""
puts "============================================================================="
puts " Running Synthesis... (this may take a few minutes)"
puts "============================================================================="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    return
}

# --- Reset implementation run ---
puts ""
puts "Resetting impl_1..."
reset_run impl_1

# --- Run implementation ---
puts ""
puts "============================================================================="
puts " Running Implementation... (this may take a few minutes)"
puts "============================================================================="
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"

if {$impl_status ne "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    return
}

# --- Generate bitstream ---
puts ""
puts "============================================================================="
puts " Generating Bitstream..."
puts "============================================================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bs_status [get_property STATUS [get_runs impl_1]]
puts "Bitstream status: $bs_status"

# --- Find the bitstream file ---
set bitfile [glob -nocomplain "C:/rvp_proj/build/vivado/rvp_nexys4.runs/impl_1/*.bit"]
if {[llength $bitfile] > 0} {
    puts ""
    puts "============================================================================="
    puts " DONE! Firmware: $fw_name"
    puts " Bitstream: [lindex $bitfile 0]"
    puts "============================================================================="
    puts ""
    puts "Now in Vivado:"
    puts "  1. Open Hardware Manager"
    puts "  2. Right-click device -> Program Device"
    puts "  3. Select the .bit file above"
    puts ""
    puts " NO need to disconnect/reconnect hardware!"
    puts " Just re-program the device."
} else {
    puts "WARNING: Bitstream file not found. Check impl_1 results."
}
