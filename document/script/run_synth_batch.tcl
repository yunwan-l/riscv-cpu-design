## =============================================================================
## run_synth_batch.tcl ??RVP ???????????????????????## =============================================================================
## ?????##   vivado -mode batch -source document/script/run_synth_batch.tcl \
##          -tclargs -config phase1_basic
##
## ???????????+ ??? + bitstream + ??????
## =============================================================================

# -----------------------------------------------------------------------------
# ???????????# -----------------------------------------------------------------------------
set config_name   "phase2_full_rv32i"
set board         "nexys4"
set top_module    "rvp_fpga_top"

if { [llength $argv] > 0 } {
    for {set i 0} {$i < [llength $argv]} {incr i} {
        set arg [lindex $argv $i]
        switch -- $arg {
            -config  { incr i; set config_name  [lindex $argv $i] }
            -board   { incr i; set board        [lindex $argv $i] }
            -top     { incr i; set top_module   [lindex $argv $i] }
            default  { puts "WARNING: Unknown argument '$arg'" }
        }
    }
}

# -----------------------------------------------------------------------------
# ??????????????document/script/???????????????
# -----------------------------------------------------------------------------
set script_dir    [file dirname [info script]]
set project_root  [file normalize [file join $script_dir .. ..]]
set project_name  "rvp_nexys4"
set project_dir   [file join "build" "vivado" $config_name]
set synth_script  [file join $project_root "synth" "vivado" "create_project.tcl"]

set log_dir       [file join $project_root "document" "log"]
set report_dir    [file join $project_root "document" "evaluate"]
set timestamp     [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set log_file      [file join $log_dir "synth_${config_name}_${timestamp}.log"]

# ??????????????????
proc log {msg} {
    global log_file
    puts $msg
    set fh [open $log_file a]
    puts $fh $msg
    close $fh
}

file mkdir $log_dir
file mkdir $report_dir

# =============================================================================
# Step 0: ???????????create_project.tcl??# =============================================================================
log "============================================================================="
log " RVP Batch Synthesis"
log "============================================================================="
log " Project root : $project_root"
log " Config       : $config_name"
log " Board        : $board"
log " Top module   : $top_module"
log " Project dir  : $project_dir"
log " Timestamp    : $timestamp"
log "============================================================================="

log "\\n>>> Step 0/7 Creating Vivado project..."

# ??-project_dir ???????????????????????????
source $synth_script

# =============================================================================
# Step 1: ???
# =============================================================================
log "\\n>>> Step 1/7 Running synthesis (synth_design)..."
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
log "   Synthesis status: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    log "ERROR: Synthesis failed!"
    # ????????????
    set synth_log_path [file join $project_root $project_dir "${project_name}.runs" "synth_1" "vivado.log"]
    if {[file exists $synth_log_path]} {
        log "\n--- Last 20 lines of synthesis log ---"
        set fh [open $synth_log_path r]
        set lines [split [read $fh] "\n"]
        close $fh
        set total [llength $lines]
        set start [expr {max(0, $total - 20)}]
        for {set i $start} {$i < $total} {incr i} {
            log "  [lindex $lines $i]"
        }
    }
    close_project
    exit 1
}

# =============================================================================
# Step 2: ???????????# =============================================================================
log "\\n>>> Step 2/7 Post-synthesis utilization report..."
open_run synth_1

set util_str [report_utilization -return_string]
log "\n============================================"
log " Resource Utilization (Post-Synthesis)"
log "============================================"
log $util_str

# ?????????
set lut_synth 0; set ff_synth 0; set bram_synth 0; set dsp_synth 0
catch { set lut_synth  [get_property SLICE_LUTS [get_utilization -type LUT]] }
catch { set ff_synth   [get_property SLICE_REGISTERS [get_utilization -type REG]] }
catch { set bram_synth [get_property BLOCKRAM [get_utilization -type BRAM]] }
catch { set dsp_synth  [get_property DSP [get_utilization -type DSP]] }

log "\n--- Key Resource Summary ---"
log "  LUTs: $lut_synth / 63400"
log "  FFs:  $ff_synth / 126800"
log "  BRAM: $bram_synth / 135"
log "  DSP:  $dsp_synth / 240"

# ???????????
set lut_pct [expr {$lut_synth * 100.0 / 63400}]
set ff_pct  [expr {$ff_synth * 100.0 / 126800}]
if {$lut_pct > 80 || $ff_pct > 80} {
    log "WARNING: Resource utilization exceeds 80% threshold!"
    log "  LUT: [format {%.1f} $lut_pct]%, FF: [format {%.1f} $ff_pct]%"
}

# =============================================================================
# Step 3: ???????????# =============================================================================
log "\\n>>> Step 3/7 Post-synthesis timing report..."
set timing_str [report_timing_summary -return_string -max_paths 10]
log "\n============================================"
log " Timing Summary (Post-Synthesis)"
log "============================================"
log $timing_str

set wns_synth ""
catch { set wns_synth [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]] }
log "\n  WNS (Worst Negative Slack): $wns_synth ns"
if {$wns_synth ne "" && $wns_synth >= 0} {
    log "  ??Timing met (WNS >= 0)"
} else {
    log "  ??Timing NOT met! (WNS < 0)"
}
close_design

# =============================================================================
# Step 4: ?????????????# =============================================================================
log "\\n>>> Step 4/7 Running implementation (place & route)..."
reset_run impl_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
log "   Implementation status: $impl_status"

# =============================================================================
# Step 5: ??????????????
# =============================================================================
log "\\n>>> Step 5/7 Post-implementation reports..."

if {$impl_status eq "route_design Complete!"} {
    open_run impl_1

    set util_impl [report_utilization -return_string]
    log "\n============================================"
    log " Resource Utilization (Post-Implementation)"
    log "============================================"
    log $util_impl

    set timing_impl [report_timing_summary -return_string -max_paths 10]
    log "\n============================================"
    log " Timing Summary (Post-Implementation)"
    log "============================================"
    log $timing_impl

    set wns_impl ""
    catch { set wns_impl [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]] }

    log "\n============================================"
    log " Final Results"
    log "============================================"
    log "  Post-Impl WNS: $wns_impl ns"
    if {$wns_impl ne "" && $wns_impl >= 0} {
        set fmax_impl [expr {1000.0 / (10.0 - $wns_impl)}]
        log "  ??Timing met"
        log "  Estimated Fmax: [format {%.2f} $fmax_impl] MHz"
        log "  Throughput (ideal CPI=1): [format {%.2f} $fmax_impl] MIPS"
    } else {
        log "  ??Timing NOT met after implementation!"
    }

    # Don't close_design here - bitstream step needs it open
} else {
    log "\nWARNING: Implementation did not complete successfully."
}

# =============================================================================
# Step 6: Generate Bitstream
# =============================================================================
log "\n>>> Step 6/7 Generating bitstream..."
set bs_path [file join $project_root $project_dir "${project_name}.runs" "impl_1" "${top_module}.bit"]

# Ensure the design is open for bitstream generation
catch { open_run impl_1 }
write_bitstream -force $bs_path
close_design

if {[file exists $bs_path]} {
    log "\n============================================"
    log " SUCCESS: Bitstream generated!"
    log "    Path: $bs_path"
    log "============================================"
} else {
    log "\n Bitstream not found at expected path:"
    log "    $bs_path"
    log "    Check Vivado log for details."
}

# =============================================================================
# Step 7: ??? Summary Markdown ???
# =============================================================================
log "\\n>>> Step 7/7 Generating summary report..."
set report_file [file join $report_dir "report_${config_name}_${timestamp}.md"]
set rf [open $report_file w]
puts $rf "# Synthesis Report: $config_name"
puts $rf ""
puts $rf "| Item | Value |"
puts $rf "|------|-------|"
puts $rf "| Config | $config_name |"
puts $rf "| Board | $board |"
puts $rf "| Top module | $top_module |"
puts $rf "| Timestamp | $timestamp |"
puts $rf "| Status | $synth_status |"
puts $rf ""
puts $rf "## Resource Utilization"
puts $rf ""
puts $rf "| Resource | Used | Available | Utilization |"
puts $rf "|----------|------|-----------|-------------|"
puts $rf "| LUT | $lut_synth | 63400 | [format {%.1f} $lut_pct]% |"
puts $rf "| FF | $ff_synth | 126800 | [format {%.1f} $ff_pct]% |"
puts $rf "| BRAM | $bram_synth | 135 | - |"
puts $rf "| DSP | $dsp_synth | 240 | - |"
puts $rf ""
puts $rf "## Timing"
puts $rf ""
puts $rf "| Metric | Value |"
puts $rf "|--------|-------|"
puts $rf "| Post-Synth WNS | $wns_synth ns |"

if {$wns_impl ne ""} {
    puts $rf "| Post-Impl WNS | $wns_impl ns |"
    if {$wns_impl >= 0} {
        set fmax_impl [expr {1000.0 / (10.0 - $wns_impl)}]
        puts $rf "| Estimated Fmax | [format {%.2f} $fmax_impl] MHz |"
    }
}
close $rf

log "\n============================================================================="
log " Summary report: $report_file"
log " Synthesis log:   $log_file"
log "============================================================================="
log ""
log " Batch synthesis for '$config_name' complete."
log "============================================================================="

close_project
exit 0

