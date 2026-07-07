## =============================================================================
## create_project_gui.tcl - RVP 工程创建脚本（GUI模式下运行）
## =============================================================================
## 用法：在 Vivado GUI 的 Tcl Console 中执行：
##   cd C:/rvp_proj
##   source synth/vivado/create_project_gui.tcl
##
## 功能：创建工程、添加源文件、设置顶层 — 然后停止。
##       综合和实现由用户在 GUI 中手动点击运行。
##      （不在脚本中调用 launch_runs / close_project / exit）
## =============================================================================

# --- 路径设置 ---
set project_root [file normalize "C:/rvp_proj"]
set filelist_path [file join $project_root "config" "rvp_core.f"]
set xdc_file      [file join $project_root "synth" "vivado" "rvp_nexys4.xdc"]
set part          "xc7a100tcsg324-1"
set top_module    "rvp_fpga_top"
set project_name  "rvp_nexys4"
set project_dir   [file join $project_root "build" "vivado"]

puts "============================================"
puts " RVP Project Creation (GUI Mode)"
puts " Project root: $project_root"
puts "============================================"

# --- 创建工程 ---
file mkdir $project_dir
create_project $project_name $project_dir -part $part -force

set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# --- 读取文件列表并添加源文件 ---
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

# --- 设置 SystemVerilog 文件类型 ---
foreach f $added_files {
    set ext [file extension $f]
    if {$ext eq ".sv" || $ext eq ".svh"} {
        set_property file_type SystemVerilog [get_files $f]
    }
}

# --- 添加约束 ---
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
    puts "  Added constraints: rvp_nexys4.xdc"
}

# --- 设置顶层模块 ---
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "============================================"
puts " Project created successfully!"
puts " Top module: $top_module"
puts ""
puts " Next steps:"
puts "   1. Click 'Run Synthesis' in Flow Navigator"
puts "   2. After synthesis, click 'Run Implementation'"
puts "   3. After implementation, click 'Generate Bitstream'"
puts "============================================"
