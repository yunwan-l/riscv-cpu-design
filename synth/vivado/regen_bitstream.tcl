# regen_bitstream.tcl — 重新生成超容量测试 bit 文件
# 包含 write_bitstream 步骤

set root_dir [pwd]

# 复制 firmware.hex
set fw_src [file join $root_dir "synth" "vivado" "firmware.hex"]
set fw_dst [file join $root_dir "rtl" "core" "firmware.hex"]
file copy -force $fw_src $fw_dst
puts "Copied firmware: $fw_src -> $fw_dst"

# 打开工程
set xpr_path [file join $root_dir "build" "vivado" "rvp_nexys4.xpr"]
open_project $xpr_path

# 重置并运行综合
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synth status: $synth_status"
if {$synth_status != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    close_project
    return -code error "Synthesis failed"
}

# 重置并运行实现 + 生成 bitstream
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "Impl status: $impl_status"

# 检查 bitstream
set bit_file [file join $root_dir "build" "vivado" "rvp_nexys4.runs" "impl_1" "rvp_fpga_top.bit"]
if {[file exists $bit_file]} {
    set bit_size [file size $bit_file]
    set mtime [file mtime $bit_file]
    puts "SUCCESS: Bitstream generated: $bit_file ($bit_size bytes)"
    puts "Bitfile mtime: [clock format $mtime -format \"%Y-%m-%d %H:%M:%S\"]"
} else {
    puts "WARNING: Bitstream not found, trying write_bitstream manually..."
    # 尝试手动生成
    open_run impl_1
    write_bitstream -force $bit_file
    if {[file exists $bit_file]} {
        set bit_size [file size $bit_file]
        puts "SUCCESS (manual): $bit_file ($bit_size bytes)"
    } else {
        puts "ERROR: Bitstream generation failed"
    }
}

close_project
puts "Done!"
