## =============================================================================
## create_piano_project.tcl
## =============================================================================
## 在 C:/rvp_proj 中创建一个全新的 Vivado 项目（rvp_piano），
## 包含钢琴外设（rvp_piano.sv）和钢琴固件（firmware_piano.hex）。
##
## 不修改已有项目（build/vivado/rvp_nexys4.xpr），新项目放在 build/vivado_piano/。
##
## 用法（在 Vivado Tcl Console 中执行）:
##   cd C:/rvp_proj
##   source synth/vivado/create_piano_project.tcl
##
## 脚本执行完后，在 Vivado 中手动运行：
##   1. Run Synthesis
##   2. Run Implementation
##   3. Generate Bitstream
##   4. Open Hardware Manager → Program Device
## =============================================================================

# -----------------------------------------------------------------------------
# 路径设置
# -----------------------------------------------------------------------------
set project_root   "C:/rvp_proj"
set project_name   "rvp_piano"
set project_dir    "$project_root/build/vivado_piano"
set part           "xc7a100tcsg324-1"
set top_module     "rvp_fpga_top"

set filelist_path  "$project_root/config/rvp_core.f"
set config_svh     "$project_root/config/rvp_config.svh"
set xdc_file       "$project_root/synth/vivado/rvp_nexys4.xdc"
set firmware_src   "$project_root/firmware_piano.hex"

puts "============================================================================="
puts " Create Piano Vivado Project"
puts "============================================================================="
puts " Project root : $project_root"
puts " Project name : $project_name"
puts " Project dir  : $project_dir"
puts " Part         : $part"
puts " Top module   : $top_module"
puts "============================================================================="

# -----------------------------------------------------------------------------
# 检查必要文件
# -----------------------------------------------------------------------------
if {![file exists $filelist_path]} {
    puts "ERROR: File list not found: $filelist_path"
    return
}
if {![file exists $config_svh]} {
    puts "ERROR: Config header not found: $config_svh"
    return
}
if {![file exists $xdc_file]} {
    puts "ERROR: XDC constraints not found: $xdc_file"
    return
}
if {![file exists $firmware_src]} {
    puts "ERROR: firmware_piano.hex not found: $firmware_src"
    puts "       Please run: python script/build_piano_firmware.py"
    return
}

# -----------------------------------------------------------------------------
# 关闭已有项目
# -----------------------------------------------------------------------------
close_project -quiet

# -----------------------------------------------------------------------------
# 创建项目
# -----------------------------------------------------------------------------
file mkdir [file dirname $project_dir]
create_project $project_name $project_dir -part $part -force

set_property target_language  Verilog      [current_project]
set_property simulator_language Mixed       [current_project]
set_property default_lib       xil_defaultlib [current_project]

# -----------------------------------------------------------------------------
# 读取文件列表 (config/rvp_core.f) 并添加 RTL 源文件
# -----------------------------------------------------------------------------
set fh [open $filelist_path r]
set filelist_lines [split [read $fh] "\n"]
close $fh

set added_files [list]

foreach line $filelist_lines {
    set trimmed [string trim $line]
    if {$trimmed eq ""} { continue }
    if {[regexp {^\s*(//|#)} $line]} { continue }

    set src_path [file join $project_root $trimmed]
    if {[file exists $src_path]} {
        lappend added_files $src_path
        add_files -norecurse $src_path
        puts "  Added: $trimmed"
    } else {
        puts "  WARNING (skipped, file not found): $trimmed"
    }
}

# 设置 .sv 文件类型为 SystemVerilog
foreach f $added_files {
    set ext [file extension $f]
    if {$ext eq ".sv" || $ext eq ".svh"} {
        set_property file_type SystemVerilog [get_files $f]
    }
}

# -----------------------------------------------------------------------------
# 添加配置头文件
# -----------------------------------------------------------------------------
add_files -norecurse $config_svh
set_property file_type {Verilog Header} [get_files $config_svh]
puts "  Added config header: config/rvp_config.svh"

# -----------------------------------------------------------------------------
# 添加约束文件 (XDC)
# -----------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse $xdc_file
# 确保约束文件用于综合和实现
set_property used_in_synthesis       true [get_files $xdc_file]
set_property used_in_implementation  true [get_files $xdc_file]
puts "  Added constraints: rvp_nexys4.xdc"

# -----------------------------------------------------------------------------
# 设置 Verilog 宏定义（与现有项目 phase2_full_rv32i 配置一致）
# -----------------------------------------------------------------------------
set verilog_defines "RVP_RV32E=0 RVP_RV32M=1 RVP_RV32C=0 RVP_ICacheEnable=0 RVP_DCacheEnable=0 RVP_ICacheReplacePolicy=0 RVP_DCacheReplacePolicy=0 RVP_Forwarding=0 RVP_BranchPredict=0 RVP_CacheStatsEnable=0"
set_property verilog_define $verilog_defines [get_filesets sources_1]
puts "  Verilog defines: $verilog_defines"

# -----------------------------------------------------------------------------
# 复制 firmware_piano.hex 为 firmware.hex
# 关键：$readmemh 综合时在 include_dirs 中搜索文件
# 需要将 firmware.hex 放在新项目目录下，并将该目录加入 include_dirs
# -----------------------------------------------------------------------------
set firmware_imports_dir [file join $project_dir ${project_name}.srcs "sources_1" "imports"]
file mkdir $firmware_imports_dir

set firmware_copy [file join $firmware_imports_dir "firmware.hex"]
file copy -force $firmware_src $firmware_copy
add_files -norecurse $firmware_copy
puts "  Added firmware: firmware_piano.hex -> firmware.hex"

# 设置 include_dirs：config 目录 + firmware.hex 所在目录
# 这样 $readmemh("firmware.hex", mem) 在综合时能找到文件
set_property include_dirs [list \
    [file join $project_root "config"] \
    $firmware_imports_dir \
] [get_filesets sources_1]
puts "  Include dirs: config, imports (for firmware.hex)"

# -----------------------------------------------------------------------------
# 设置顶层模块
# -----------------------------------------------------------------------------
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

puts "============================================================================="
puts " Project '$project_name' created successfully!"
puts " Location: $project_dir/${project_name}.xpr"
puts "============================================================================="
puts ""
puts " Next steps (in Vivado GUI):"
puts "   1. Run Synthesis"
puts "   2. Run Implementation"
puts "   3. Generate Bitstream"
puts "   4. Open Hardware Manager -> Program Device"
puts ""
puts " After programming, run on PC:"
puts "   python script/pc_piano.py COMx"
puts "============================================================================="
