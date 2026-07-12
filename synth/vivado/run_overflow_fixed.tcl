# run_overflow_fixed.tcl — 超容量测试综合脚本 (修复路径问题)
# 使用绝对路径，避免 info script 在 batch 模式下的问题

# 设置根目录 (Vivado 从项目根目录启动)
set root_dir [pwd]

# 复制 firmware.hex (绝对路径)
set fw_src [file join $root_dir "synth" "vivado" "firmware.hex"]
set fw_dst [file join $root_dir "rtl" "core" "firmware.hex"]
file copy -force $fw_src $fw_dst
puts "Copied: $fw_src -> $fw_dst"

# 打开工程 (绝对路径)
set xpr_path [file join $root_dir "build" "vivado" "rvp_nexys4.xpr"]
open_project $xpr_path

# 重置并运行综合
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "Synthesis complete"

# 检查综合结果
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synth status: $synth_status"
if {$synth_status != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    close_project
    return -code error "Synthesis failed"
}

# 重置并运行实现
reset_run impl_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1
puts "Implementation complete"

# 检查实现结果
set impl_status [get_property STATUS [get_runs impl_1]]
puts "Impl status: $impl_status"

# 检查 bitstream
set bit_file [file join $root_dir "build" "vivado" "rvp_nexys4.runs" "impl_1" "rvp_fpga_top.bit"]
if {[file exists $bit_file]} {
    set bit_size [file size $bit_file]
    puts "SUCCESS: Bitstream generated: $bit_file ($bit_size bytes)"
    # 打印修改时间
    set mtime [file mtime $bit_file]
    puts "Bitfile mtime: [clock format $mtime -format \"%Y-%m-%d %H:%M:%S\"]"
} else {
    puts "ERROR: Bitstream not found at $bit_file"
}

close_project
puts "Done!"
