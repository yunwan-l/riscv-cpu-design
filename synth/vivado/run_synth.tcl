## =============================================================================
## run_synth.tcl - RVP Vivado 综合脚本（一键综合 + 资源/时序报告）
## =============================================================================
## 用法：
##   vivado -mode batch -source synth/vivado/run_synth.tcl
##
## 功能：
##   1. 调用 create_project.tcl 创建工程
##   2. 运行综合 (synth_design)
##   3. 运行实现 (opt_design + place_design + route_design)
##   4. 生成资源占用报告和时序报告
##   5. 输出 Fmax / LUT / FF / BRAM 关键指标
## =============================================================================

set project_root  [file normalize [file join [file dirname [info script]] .. ..]]
set script_dir    [file dirname [info script]]

puts "============================================================================="
puts " RVP Vivado Synthesis Flow"
puts " Project root: $project_root"
puts "============================================================================="

# -----------------------------------------------------------------------------
# Step 1: 创建工程（调用 create_project.tcl）
# -----------------------------------------------------------------------------
puts "\n>>> Step 1: Creating Vivado project..."

# 使用 source 调用 create_project.tcl，传递 top=rvp_fpga_top
source [file join $script_dir "create_project.tcl"]

# 将 firmware.hex 拷贝到综合运行目录，确保 $readmemh 能找到
set firmware_src [file join $script_dir "firmware.hex"]
set synth_run_dir [file join $project_root "build" "vivado" "rvp_nexys4.runs" "synth_1"]
file mkdir $synth_run_dir
if {[file exists $firmware_src]} {
    file copy -force $firmware_src [file join $synth_run_dir "firmware.hex"]
    puts "   Copied firmware.hex to synth run directory"
} else {
    puts "   WARNING: firmware.hex not found! BRAM will be uninitialized."
}

# -----------------------------------------------------------------------------
# Step 2: 综合设计
# -----------------------------------------------------------------------------
puts "\n>>> Step 2: Running synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# 检查综合结果
set synth_status [get_property STATUS [get_runs synth_1]]
puts "   Synthesis status: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed! Status: $synth_status"
    # 打开综合后的设计检查错误
    open_run synth_1
    puts "\n--- Critical Warnings ---"
    foreach msg [get_msg_config -severity {CRITICAL WARNING}] {
        puts "  $msg"
    }
    close_design
    exit 1
}

# -----------------------------------------------------------------------------
# Step 3: 打开综合后的设计，提取资源报告
# -----------------------------------------------------------------------------
puts "\n>>> Step 3: Extracting utilization report..."
open_run synth_1

# 资源利用率
set util [report_utilization -return_string]
puts "\n============================================"
puts " Resource Utilization (Post-Synthesis)"
puts "============================================"
puts $util

# 提取关键资源数据
proc parse_util {text pattern} {
    foreach line [split $text "\n"] {
        if {[regexp $pattern $line -> v]} {return [string trim $v]}
    }
    return "N/A"
}
set lut_count  [parse_util $util {Slice LUTs.*\|\s*(\d+)}]
set ff_count   [parse_util $util {Slice Registers.*\|\s*(\d+)}]
set bram_count [parse_util $util {Block RAM Tile.*\|\s*(\d+)}]
set dsp_count  [parse_util $util {DSPs.*\|\s*(\d+)}]

puts "\n============================================"
puts " Key Resource Summary"
puts "============================================"
puts "  LUTs:     $lut_count / 63400  ([format "%.1f" [expr {$lut_count * 100.0 / 63400}]]%)"
puts "  FFs:      $ff_count / 126800  ([format "%.1f" [expr {$ff_count * 100.0 / 126800}]]%)"
puts "  BRAM:     $bram_count / 135"
puts "  DSP:      $dsp_count / 240"

# -----------------------------------------------------------------------------
# Step 4: 时序报告
# -----------------------------------------------------------------------------
puts "\n>>> Step 4: Extracting timing report..."

# 获取时序摘要
set timing_summary [report_timing_summary -return_string -max_paths 10]
puts "\n============================================"
puts " Timing Summary (Post-Synthesis)"
puts "============================================"
puts $timing_summary

# 提取 WNS (Worst Negative Slack)
# clk_soc 域周期为 80ns (12.5MHz)，sys_clk_pin 域周期为 10ns (100MHz)
# 关键路径在 clk_soc 域，使用 80ns 计算 Fmax
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
if {$wns eq ""} {
    set wns "N/A"
}

puts "\n============================================"
puts " Timing Summary"
puts "============================================"
puts "  WNS (Worst Negative Slack): $wns ns"
if {$wns ne "N/A" && $wns >= 0} {
    # clk_soc 域：周期 80ns (12.5MHz)，Fmax = 1000 / (80 - WNS)
    set fmax [expr {1000.0 / (80.0 - $wns)}]
    puts "  Estimated Fmax (clk_soc): [format "%.2f" $fmax] MHz"
} else {
    puts "  Timing not met (or no timing paths)"
}

close_design

# -----------------------------------------------------------------------------
# Step 5: 运行实现（布局布线）
# -----------------------------------------------------------------------------
puts "\n>>> Step 5: Running implementation (place & route)..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "   Implementation status: $impl_status"

# -----------------------------------------------------------------------------
# Step 6: 实现后资源/时序报告
# -----------------------------------------------------------------------------
if {$impl_status eq "route_design Complete!"} {
    puts "\n>>> Step 6: Extracting post-implementation reports..."
    open_run impl_1

    set util_impl [report_utilization -return_string]
    puts "\n============================================"
    puts " Resource Utilization (Post-Implementation)"
    puts "============================================"
    puts $util_impl

    set timing_impl [report_timing_summary -return_string -max_paths 10]
    puts "\n============================================"
    puts " Timing Summary (Post-Implementation)"
    puts "============================================"
    puts $timing_impl

    set wns_impl [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
    puts "\n============================================"
    puts " Final Summary"
    puts "============================================"
    puts "  Post-Impl WNS: $wns_impl ns"
    if {$wns_impl ne "" && $wns_impl >= 0} {
        set fmax_impl [expr {1000.0 / (80.0 - $wns_impl)}]
        puts "  Final Fmax (clk_soc, 12.5MHz base): [format "%.2f" $fmax_impl] MHz"
        puts "  Throughput (ideal CPI=1): [format "%.2f" $fmax_impl] MIPS"
    } else {
        puts "  Timing NOT met after implementation"
    }

    close_design
} else {
    puts "\nWARNING: Implementation did not complete successfully."
    puts "Check the Vivado log for details."
}

# -----------------------------------------------------------------------------
# Step 7: 生成 Bitstream（可选）
# -----------------------------------------------------------------------------
puts "\n>>> Step 7: Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bitstream_path [file join $project_root "build" "vivado" "rvp_nexys4.runs" "impl_1" "rvp_fpga_top.bit"]
if {[file exists $bitstream_path]} {
    puts "\n============================================"
    puts " SUCCESS: Bitstream generated!"
    puts " Path: $bitstream_path"
    puts "============================================"
} else {
    puts "\nWARNING: Bitstream not found at expected location."
    puts "Expected: $bitstream_path"
}

puts "\n============================================================================="
puts " Synthesis flow complete."
puts "============================================================================="

# 关闭工程
close_project
