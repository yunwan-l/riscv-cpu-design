## =============================================================================
## run_direct.tcl - RVP 直接综合流程（绕过 launch_runs 的 TclStackFree bug）
## =============================================================================
## 策略：
##   1. 使用 catch 包裹 synth_design，捕获 TclStackFree 错误
##   2. 如果设计仍在内存中，继续实现和比特流生成
##   3. 使用 -flatten_hierarchy none 减少层次展平可能的 bug
## =============================================================================

set script_dir   [file dirname [info script]]
set project_root [file normalize [file join $script_dir .. ..]]

puts "============================================================================="
puts " RVP Direct Synthesis Flow (with TclStackFree workaround)"
puts " Project root: $project_root"
puts "============================================================================="

# -----------------------------------------------------------------------------
# Step 1: 创建内存工程
# -----------------------------------------------------------------------------
create_project -in_memory -part xc7a100tcsg324-1
set_property default_lib xil_defaultlib [current_project]
set_property target_language Verilog [current_project]

# -----------------------------------------------------------------------------
# Step 2: 设置 include_dirs
# -----------------------------------------------------------------------------
set_property include_dirs [list \
    [file join $project_root "config"] \
    [file join $project_root "synth" "vivado"] \
] [current_fileset]

# -----------------------------------------------------------------------------
# Step 3: 设置 Verilog 宏定义
# -----------------------------------------------------------------------------
set_property verilog_define {RVP_RV32E=0 RVP_RV32M=1 RVP_RV32C=0 RVP_ICacheEnable=0 RVP_DCacheEnable=0 RVP_ICacheReplacePolicy=0 RVP_DCacheReplacePolicy=0 RVP_Forwarding=0 RVP_BranchPredict=0 RVP_CacheStatsEnable=0} [current_fileset]

# -----------------------------------------------------------------------------
# Step 4: 复制 firmware.hex 到 rtl/core/
# -----------------------------------------------------------------------------
file copy -force [file join $script_dir "firmware.hex"] [file join $project_root "rtl" "core" "firmware.hex"]
puts "Copied firmware.hex to rtl/core/"

# -----------------------------------------------------------------------------
# Step 5: 读取所有 SystemVerilog 源文件
# -----------------------------------------------------------------------------
read_verilog -sv [list \
    [file join $project_root "rtl" "rvp_pkg.sv"] \
    [file join $project_root "rtl" "core" "rvp_alu.sv"] \
    [file join $project_root "rtl" "core" "rvp_branch_unit.sv"] \
    [file join $project_root "rtl" "core" "rvp_core_pipeline.sv"] \
    [file join $project_root "rtl" "core" "rvp_data_mem.sv"] \
    [file join $project_root "rtl" "core" "rvp_decoder.sv"] \
    [file join $project_root "rtl" "core" "rvp_forward_unit.sv"] \
    [file join $project_root "rtl" "periph" "rvp_gpio.sv"] \
    [file join $project_root "rtl" "core" "rvp_hazard_unit.sv"] \
    [file join $project_root "rtl" "cache" "rvp_icache_pmru8.sv"] \
    [file join $project_root "rtl" "core" "rvp_imm_generator.sv"] \
    [file join $project_root "rtl" "core" "rvp_instr_mem.sv"] \
    [file join $project_root "rtl" "core" "rvp_multdiv.sv"] \
    [file join $project_root "rtl" "core" "rvp_pipeline_regs.sv"] \
    [file join $project_root "rtl" "core" "rvp_register_file.sv"] \
    [file join $project_root "rtl" "rvp_soc.sv"] \
    [file join $project_root "rtl" "periph" "rvp_timer.sv"] \
    [file join $project_root "rtl" "periph" "rvp_uart.sv"] \
    [file join $project_root "rtl" "rvp_fpga_top.sv"] \
]
puts "Read all SystemVerilog source files"

# -----------------------------------------------------------------------------
# Step 6: 读取 XDC 约束文件
# -----------------------------------------------------------------------------
set xdc_file [file join $script_dir "rvp_nexys4.xdc"]
puts "Reading XDC: $xdc_file"
read_xdc $xdc_file

# -----------------------------------------------------------------------------
# Step 7: 综合（使用 catch 捕获 TclStackFree 错误）
# -----------------------------------------------------------------------------
set_msg_config -id {Synth 8-3331} -suppress

puts "\n============================================================================="
puts " Step 7: Running synth_design (with catch)..."
puts "============================================================================="

set synth_err [catch {synth_design -top rvp_fpga_top -part xc7a100tcsg324-1 -flatten_hierarchy none} synth_result]

if {$synth_err} {
    puts "WARNING: synth_design reported an error:"
    puts "  $synth_result"
    puts "Checking if design is still in memory..."
    set d [current_design -quiet]
    if {$d ne ""} {
        puts "SUCCESS: Design is still in memory! Continuing with implementation..."
    } else {
        puts "ERROR: Design was lost after synthesis error. Cannot continue."
        # 清理
        file delete -force [file join $project_root "rtl" "core" "firmware.hex"]
        return
    }
} else {
    puts "Synthesis completed successfully."
}

# 设置设计属性
catch {set_property CONFIG_VOLTAGE 3.3 [current_design]}
catch {set_property CFGBVS VCCO [current_design]}
catch {set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]}
catch {set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]}

# 综合后资源报告（可能失败，忽略错误）
puts "\n============================================"
puts " Post-Synthesis Utilization"
puts "============================================"
catch {report_utilization}

# 保存综合 checkpoint（关键步骤，立即保存）
set synth_dcp [file join $project_root "build" "vivado" "rvp_nexys4_synth.dcp"]
file mkdir [file dirname $synth_dcp]
catch {
    write_checkpoint -force $synth_dcp
    puts "Saved synthesis checkpoint: $synth_dcp"
}

# -----------------------------------------------------------------------------
# Step 8: 优化
# -----------------------------------------------------------------------------
puts "\n============================================================================="
puts " Step 8: Running opt_design..."
puts "============================================================================="
set opt_err [catch {opt_design} opt_result]
if {$opt_err} {
    puts "WARNING: opt_design reported: $opt_result"
    set d [current_design -quiet]
    if {$d eq ""} {
        puts "ERROR: Design lost after opt_design."
        file delete -force [file join $project_root "rtl" "core" "firmware.hex"]
        return
    }
}

# -----------------------------------------------------------------------------
# Step 9: 布局
# -----------------------------------------------------------------------------
puts "\n============================================================================="
puts " Step 9: Running place_design..."
puts "============================================================================="
set place_err [catch {place_design} place_result]
if {$place_err} {
    puts "WARNING: place_design reported: $place_result"
    set d [current_design -quiet]
    if {$d eq ""} {
        puts "ERROR: Design lost after place_design."
        file delete -force [file join $project_root "rtl" "core" "firmware.hex"]
        return
    }
}

# -----------------------------------------------------------------------------
# Step 10: 布线
# -----------------------------------------------------------------------------
puts "\n============================================================================="
puts " Step 10: Running route_design..."
puts "============================================================================="
set route_err [catch {route_design} route_result]
if {$route_err} {
    puts "WARNING: route_design reported: $route_result"
    set d [current_design -quiet]
    if {$d eq ""} {
        puts "ERROR: Design lost after route_design."
        file delete -force [file join $project_root "rtl" "core" "firmware.hex"]
        return
    }
}

# 实现后报告
puts "\n============================================"
puts " Post-Implementation Utilization"
puts "============================================"
catch {report_utilization}

puts "\n============================================"
puts " Post-Implementation Timing"
puts "============================================"
catch {report_timing_summary -max_paths 10}

# 保存布线后 checkpoint
catch {
    write_checkpoint -force [file join $project_root "build" "vivado" "rvp_nexys4_route.dcp"]
    puts "Saved routed checkpoint"
}

# -----------------------------------------------------------------------------
# Step 11: 生成 Bitstream
# -----------------------------------------------------------------------------
puts "\n============================================================================="
puts " Step 11: Generating bitstream..."
puts "============================================================================="
set bitfile [file join $project_root "build" "vivado" "rvp_nexys4.bit"]
file mkdir [file dirname $bitfile]
set bit_err [catch {write_bitstream -force $bitfile} bit_result]
if {$bit_err} {
    puts "WARNING: write_bitstream reported: $bit_result"
}

if {[file exists $bitfile]} {
    puts "\n============================================"
    puts " SUCCESS: Bitstream generated!"
    puts " Size: [file size $bitfile] bytes"
    puts " Path: $bitfile"
    puts "============================================"
} else {
    puts "\nERROR: Bitstream not found at $bitfile"
}

# -----------------------------------------------------------------------------
# Step 12: 提取关键指标
# -----------------------------------------------------------------------------
catch {
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
    puts "\n============================================"
    puts " Final Summary"
    puts "============================================"
    puts "  WNS: $wns ns"
    if {$wns ne "" && $wns >= 0} {
        set fmax [expr {1000.0 / (80.0 - $wns)}]
        puts "  Fmax (clk_soc, 12.5MHz base): [format "%.2f" $fmax] MHz"
    } else {
        puts "  Timing NOT met"
    }
}

# 资源摘要
catch {
    set util_rpt [report_utilization -return_string]
    regexp {Slice LUTs\*\s*\|\s*(\d+)} $util_rpt -> lut_count
    regexp {Slice Registers\*\s*\|\s*(\d+)} $util_rpt -> ff_count
    regexp {Block RAM Tile\*\s*\|\s*(\d+\.?\d*)} $util_rpt -> bram_count
    regexp {DSPs\*\s*\|\s*(\d+)} $util_rpt -> dsp_count
    if {[info exists lut_count]} {
        puts "  LUTs:  $lut_count / 63400"
    }
    if {[info exists ff_count]} {
        puts "  FFs:   $ff_count / 126800"
    }
    if {[info exists bram_count]} {
        puts "  BRAM:  $bram_count / 135"
    }
    if {[info exists dsp_count]} {
        puts "  DSP:   $dsp_count / 240"
    }
}

# 清理
file delete -force [file join $project_root "rtl" "core" "firmware.hex"]
puts "\nCleaned up temporary firmware.hex copy"

# 不关闭工程，方便用户继续操作（如打开 Hardware Manager 烧录）
# catch {close_project}
puts "\n============================================================================="
puts " Direct synthesis flow complete."
puts " Project kept open for Hardware Manager / further debugging."
puts "============================================================================="
