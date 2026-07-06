## =============================================================================
## run_synth.tcl - RVP Synthesis Flow Script
## =============================================================================
## Creates the Vivado project, runs synthesis, and generates resource
## utilization and timing reports.
##
## Usage (from project root):
##   vivado -mode batch -source synth/vivado/run_synth.tcl -tclargs [options]
##
## Options (all optional, defaults shown):
##   -board        nexys4             Target board: nexys4 | zybo
##   -config       phase2_full_rv32i  Named config from config/rvp_configs.yaml
##   -project_name rvp_nexys4         Vivado project name
##   -project_dir  build/vivado       Output directory
##   -top          rvp_core           Top-level module
##   -jobs         4                  Number of parallel synthesis jobs
##
## Examples:
##   vivado -mode batch -source synth/vivado/run_synth.tcl \
##          -tclargs -board nexys4 -config phase3_icache_lru
##
##   vivado -mode batch -source synth/vivado/run_synth.tcl \
##          -tclargs -config phase3_full -jobs 8
## =============================================================================

# -----------------------------------------------------------------------------
# Parse command-line arguments
# -----------------------------------------------------------------------------
set board         "nexys4"
set config_name   "phase2_full_rv32i"
set project_name  "rvp_nexys4"
set project_dir   "build/vivado"
set top_module    "rvp_core"
set num_jobs      4

if { [llength $argv] > 0 } {
    for {set i 0} {$i < [llength $argv]} {incr i} {
        set arg [lindex $argv $i]
        switch -- $arg {
            -board        { incr i; set board        [lindex $argv $i] }
            -config       { incr i; set config_name  [lindex $argv $i] }
            -project_name { incr i; set project_name [lindex $argv $i] }
            -project_dir  { incr i; set project_dir  [lindex $argv $i] }
            -top          { incr i; set top_module   [lindex $argv $i] }
            -jobs         { incr i; set num_jobs     [lindex $argv $i] }
            default {
                puts "WARNING: Unknown argument '$arg'"
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Resolve script and project paths
# -----------------------------------------------------------------------------
set script_dir   [file dirname [info script]]
set project_root [file normalize [file join $script_dir .. ..]]
set create_proj   [file join $script_dir "create_project.tcl"]

set report_dir [file join $project_root $project_dir "reports" ${config_name}]
file mkdir $report_dir

puts "============================================================================="
puts " RVP Synthesis Flow"
puts "============================================================================="
puts " Board         : $board"
puts " Config         : $config_name"
puts " Top module    : $top_module"
puts " Jobs           : $num_jobs"
puts " Report dir    : $report_dir"
puts "============================================================================="

# -----------------------------------------------------------------------------
# Step 1: Create the Vivado project (calls create_project.tcl)
# -----------------------------------------------------------------------------
puts ""
puts "--- Step 1: Creating Vivado project ---"
puts ""

# Source the project creation script with arguments
set argv [list \
    -project_name $project_name \
    -project_dir  $project_dir \
    -board        $board \
    -config       $config_name \
    -top          $top_module \
]
source $create_proj

# Re-open the project (create_project.tcl leaves it open, but ensure)
open_project [file join $project_root $project_dir ${project_name}.xpr]

puts ""
puts "--- Project created and opened ---"
puts ""

# -----------------------------------------------------------------------------
# Step 2: Run synthesis
# -----------------------------------------------------------------------------
puts "--- Step 2: Running synthesis ---"
puts ""

# Set number of jobs for parallel synthesis
set_param general.maxThreads $num_jobs

# Launch synthesis
reset_run synth_1
launch_run synth_1 -jobs $num_jobs
wait_on_run synth_1

# Check synthesis status
set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_status ne "synth_design Complete"} {
    puts "ERROR: Synthesis failed with status: $synth_status"
    exit 1
}

puts ""
puts "--- Synthesis completed successfully ---"
puts ""

# -----------------------------------------------------------------------------
# Step 3: Generate reports
# -----------------------------------------------------------------------------

# --- 3a. Utilization report ---
puts "--- Step 3a: Generating utilization report ---"
set util_report [file join $report_dir "utilization.rpt"]
# Open synthesized design for report generation
open_run synth_1

# Write Vivado's built-in utilization report
write_report -force -report_file $util_report -type utilization

# Also capture the summary on console
puts ""
puts "=== Resource Utilization Summary ==="
report_utilization -hierarchical -hierarchical_depth 3
report_utilization -slr
puts ""

# Save utilization summary to report file
set fh [open $util_report "a"]
puts $fh ""
puts $fh "==================================================================="
puts $fh " RVP Synthesis Utilization Report"
puts $fh "==================================================================="
puts $fh " Config: $config_name"
puts $fh " Board:  $board"
puts $fh " Top:    $top_module"
puts $fh " Date:   [clock format [clock seconds]]"
puts $fh "==================================================================="
puts $fh ""
close $fh

# Re-run report_utilization to append to the file
report_utilization -file $util_report -append
report_utilization -hierarchical -file $util_report -append

# --- 3b. Timing report ---
puts "--- Step 3b: Generating timing report ---"
set timing_report [file join $report_dir "timing.rpt"]

report_timing_summary -file $timing_report
report_timing_summary -max_paths 10 -file $timing_report -append

# Print timing summary to console
puts ""
puts "=== Timing Summary ==="
report_timing_summary
puts ""

# --- 3c. Clock utilization ---
set clock_report [file join $report_dir "clocks.rpt"]
report_clocks -file $clock_report

# --- 3d. Power report ---
puts "--- Step 3c: Generating power report ---"
set power_report [file join $report_dir "power.rpt"]
report_power -file $power_report

puts ""
puts "=== Power Summary ==="
report_power -hier
puts ""

# --- 3e. Design summary ---
set summary_file [file join $report_dir "synth_summary.txt"]
set fh [open $summary_file "w"]
puts $fh "==================================================================="
puts $fh " RVP Synthesis Summary"
puts $fh "==================================================================="
puts $fh " Project:        $project_name"
puts $fh " Configuration:  $config_name"
puts $fh " Board:          $board"
puts $fh " Top module:     $top_module"
puts $fh " Target part:    [get_property PART [current_project]]"
puts $fh " Synthesis jobs: $num_jobs"
puts $fh " Date:           [clock format [clock seconds]]"
puts $fh "==================================================================="
puts $fh ""
puts $fh "Reports generated:"
puts $fh "  Utilization: $util_report"
puts $fh "  Timing:      $timing_report"
puts $fh "  Clocks:      $clock_report"
puts $fh "  Power:       $power_report"
puts $fh "==================================================================="
close $fh

# Close the synthesized design
close_design

# -----------------------------------------------------------------------------
# Step 4: Print final summary
# -----------------------------------------------------------------------------
puts "============================================================================="
puts " RVP Synthesis Flow Complete"
puts "============================================================================="
puts " Configuration:  $config_name"
puts " Project:         $project_name"
puts " Synthesis status: $synth_status"
puts ""
puts " Reports saved to: $report_dir"
puts "   - utilization.rpt   (resource usage)"
puts "   - timing.rpt         (timing summary + critical paths)"
puts "   - clocks.rpt         (clock resources)"
puts "   - power.rpt          (power estimation)"
puts "   - synth_summary.txt  (overall summary)"
puts "============================================================================="
