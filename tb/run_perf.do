# =============================================================================
# run_perf.do — ModelSim 性能仿真脚本
# =============================================================================
# 用法（在项目根目录执行）：
#   vsim -do tb/run_perf.do
#
# 需要通过环境变量 HEX_DIR 指定 hex 文件目录，或使用默认路径
# =============================================================================

# 退出时关闭 Waveform
onbreak {resume}
onerror {resume}

# --- 创建工作库 ---
if {[file exists work]} {
  file delete -force work
}
vlib work
vmap work work

# --- 编译 RTL ---
puts "=========================================================="
puts "  编译 RTL..."
puts "=========================================================="
vlog -sv -f config/rvp_core.f

# --- 编译 Testbench ---
puts "=========================================================="
puts "  编译 Testbench..."
puts "=========================================================="
vlog -sv tb/tb_perf.sv

# --- 运行仿真 ---
puts "=========================================================="
puts "  启动仿真..."
puts "=========================================================="

# 获取 HEX_DIR（优先用环境变量，否则用默认路径）
if {[info exists env(HEX_DIR)]} {
  set hex_dir $env(HEX_DIR)
} else {
  set hex_dir "sw/tests"
}

puts "  HEX 目录: $hex_dir"

vsim -t 1ps -voptargs="+acc" -do "run -all" -do "quit -f" tb_perf +HEX_DIR=$hex_dir
