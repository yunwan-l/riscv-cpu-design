# regen_overflow_bit.tcl — 重新生成超容量测试 bit 文件
# 禁用 WebTalk 防止卡住

# Vivado batch mode

set root_dir [pwd]

# 确认 firmware.hex 已就位
set fw_src [file join $root_dir "synth" "vivado" "firmware.hex"]
set fw_dst [file join $root_dir "rtl" "core" "firmware.hex"]
file copy -force $fw_src $fw_dst
puts "firmware.hex 已复制: $fw_src -> $fw_dst"
puts "firmware.hex 行数: [llength [split [read [open $fw_src r]] \n]]"

# 打开工程
set xpr_path [file join $root_dir "build" "vivado" "rvp_nexys4.xpr"]
puts "正在打开工程: $xpr_path"
open_project $xpr_path

# 重置综合
puts "正在重置综合..."
reset_run synth_1
puts "正在启动综合..."
launch_runs synth_1 -jobs 4
puts "等待综合完成..."
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "综合状态: $synth_status"
if {$synth_status != "synth_design Complete!"} {
    puts "错误: 综合失败!"
    close_project
    exit 1
}

# 重置实现 + 生成 bitstream
puts "正在重置实现..."
reset_run impl_1
puts "正在启动实现+bitstream生成..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
puts "等待实现完成..."
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "实现状态: $impl_status"

# 检查 bitstream
set bit_file [file join $root_dir "build" "vivado" "rvp_nexys4.runs" "impl_1" "rvp_fpga_top.bit"]
if {[file exists $bit_file]} {
    set bit_size [file size $bit_file]
    set mtime [file mtime $bit_file]
    puts "成功! Bitstream: $bit_file"
    puts "大小: $bit_size 字节"
    puts "时间: [clock format $mtime -format \"%Y-%m-%d %H:%M:%S\"]"
} else {
    puts "警告: Bitstream 未找到, 尝试手动生成..."
    open_run impl_1
    write_bitstream -force $bit_file
    if {[file exists $bit_file]} {
        puts "成功(手动): $bit_file ([file size $bit_file] 字节)"
    }
}

close_project
puts "完成!"
exit 0
