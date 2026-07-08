## =============================================================================
## run_synth_standalone.tcl - RVP 独立综合脚本（不依赖 source�?
## =============================================================================
## 用法：vivado -mode batch -source synth/vivado/run_synth_standalone.tcl
## =============================================================================

# -----------------------------------------------------------------------------
# 手动设置路径（不依赖 info script�?
# -----------------------------------------------------------------------------
set project_root [file normalize "C:/rvp_proj"]
set script_dir   [file join $project_root "synth" "vivado"]
set filelist_path [file join $project_root "config" "rvp_core.f"]
set config_svh    [file join $project_root "config" "rvp_config.svh"]
set configs_yaml  [file join $project_root "config" "rvp_configs.yaml"]
set xdc_file      [file join $script_dir "rvp_nexys4.xdc"]
set part          "xc7a100tcsg324-1"
set top_module    "rvp_fpga_top"
set config_name   "phase2_full_rv32i"
set project_name  "rvp_nexys4"
set project_dir   [file join $project_root "build" "vivado"]

puts "============================================================================="
puts " RVP Vivado Synthesis (Standalone)"
puts " Project root: $project_root"
puts " Top module:   $top_module"
puts "============================================================================="

# -----------------------------------------------------------------------------
# 解析 YAML 配置
# -----------------------------------------------------------------------------
proc parse_config_yaml {yaml_path config_name} {
    set fh [open $yaml_path r]
    set lines [split [read $fh] "\n"]
    close $fh
    set in_config 0
    set result [dict create]
    foreach line $lines {
        set trimmed [string trim $line]
        if {$trimmed eq "" || [string index $trimmed 0] eq "#"} { continue }
        if {![regexp {^\s} $line] && [regexp {^([\w]+):\s*$} $line -> name]} {
            set in_config [expr {$name eq $config_name}]
            continue
        }
        if {$in_config} {
            if {[regexp {^\s*([A-Za-z_]\w*)\s*:\s*(.+?)\s*$} $line -> key val]} {
                regsub {\s+#.*$} $val "" val
                set val [string trim $val "\"' "]
                dict set result $key $val
            }
        }
    }
    return $result
}

set config_params [parse_config_yaml $configs_yaml $config_name]
puts "Config: $config_name"
dict for {k v} $config_params { puts "  $k = $v" }

# 构建 Verilog defines
set define_list [list]
dict for {key val} $config_params {
    lappend define_list "RVP_${key}=${val}"
}
set verilog_define_str [join $define_list " "]

# -----------------------------------------------------------------------------
# 创建工程
# -----------------------------------------------------------------------------
file mkdir $project_dir
close_project -quiet
create_project $project_name $project_dir -part $part -force

set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# -----------------------------------------------------------------------------
# 读取文件列表并添加源文件
# -----------------------------------------------------------------------------
set fh [open $filelist_path r]
set filelist_lines [split [read $fh] "\n"]
close $fh

set added_files [list]
foreach line $filelist_lines {
    set trimmed [string trim $line]
    if {$trimmed eq "" || [regexp {^\s*(//|#)} $line]} { continue }
    set src_path [file join $project_root $trimmed]
    if {[file exists $src_path]} {
        lappend added_files $src_path
        add_files -norecurse $src_path
        puts "  Added: $trimmed"
    } else {
        puts "  WARNING (not found): $trimmed"
    }
}

# 设置 SystemVerilog 文件类型
# Vivado 默认�?.sv 识别�?SystemVerilog，但显式设置更安�?
foreach f $added_files {
    set ext [file extension $f]
    if {$ext eq ".sv" || $ext eq ".svh"} {
        set_property file_type SystemVerilog [get_files $f]
    }
}

# 注意：当前流水线架构不使�?rvp_config.svh，不需要添�?
# 注意：当前文件没�?\`ifdef 指令，不需要设�?verilog_define

# 添加约束
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "  Added constraints: rvp_nexys4.xdc"
}

# 注意：不添加 program.hex，不设置 used_in_synthesis
# 指令存储器使�?initial 块填�?NOP，不依赖外部 hex 文件
# 仿真�?testbench 通过 $readmemh 覆盖存储器内�?

# 设置顶层模块
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

puts "\n============================================================================="
puts " Project created. Starting synthesis..."
puts "============================================================================="

# -----------------------------------------------------------------------------
# 运行综合
# -----------------------------------------------------------------------------
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    # 读取综合日志中的错误
    set synth_log [file join $project_dir "${project_name}.runs" "synth_1" "runme.log"]
    if {[file exists $synth_log]} {
        puts "\n--- Last 30 lines of synth log ---"
        set log_fh [open $synth_log r]
        set log_lines [split [read $log_fh] "\n"]
        close $log_fh
        set total [llength $log_lines]
        set start [expr {max(0, $total - 30)}]
        for {set i $start} {$i < $total} {incr i} {
            puts "  [lindex $log_lines $i]"
        }
    }
    close_project
    exit 1
}

# -----------------------------------------------------------------------------
# 提取综合后资源报�?
# -----------------------------------------------------------------------------
puts "\n============================================================================="
puts " Extracting reports..."
puts "============================================================================="

open_run synth_1
report_utilization
report_timing_summary -max_paths 5
close_design

# -----------------------------------------------------------------------------
# 运行实现
# -----------------------------------------------------------------------------
puts "\nStarting implementation..."
reset_run impl_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"

if {$impl_status eq "route_design Complete!"} {
    open_run impl_1
    puts "\n============================================================================="
    puts " Post-Implementation Reports"
    puts "============================================================================="
    report_utilization
    report_timing_summary -max_paths 5
    
    # 生成 bitstream
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    
    set bitstream [file join $project_dir "${project_name}.runs" "impl_1" "${top_module}.bit"]
    if {[file exists $bitstream]} {
        puts "\nSUCCESS: Bitstream generated at $bitstream"
    }
    close_design
} else {
    puts "WARNING: Implementation incomplete"
}

close_project
puts "\n============================================================================="
puts " Done!"
puts "============================================================================="
