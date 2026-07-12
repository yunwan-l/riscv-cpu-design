# run_overflow.tcl — 超容量测试综合脚本
# 简化版: 直接在当前进程中运行综合+实现+bitstream (不使用launch_runs)

set proj_name "rvp_nexys4"
set proj_dir [file normalize "build/vivado"]
set xpr_path [file join $proj_dir "${proj_name}.xpr"]

# 复制 firmware.hex (必须在 open_project 之前，用绝对路径)
set src_dir [file normalize [file dirname [info script]]]
set root_dir [file normalize "$src_dir/../.."]
file copy -force [file join $src_dir "firmware.hex"] [file join $root_dir "rtl" "core" "firmware.hex"]
puts "firmware.hex copied to rtl/core/"

# 打开工程
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

# 生成bitstream (包含在impl_1中)
set bit_file [file join $proj_dir "${proj_name}.runs" "impl_1" "rvp_fpga_top.bit"]
if {[file exists $bit_file]} {
    set bit_size [file size $bit_file]
    puts "SUCCESS: Bitstream generated: $bit_file ($bit_size bytes)"
} else {
    puts "ERROR: Bitstream not found at $bit_file"
}

close_project
puts "Done!"
