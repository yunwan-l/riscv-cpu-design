# =============================================================================
# wave_alu.do — ALU 仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_alu.do -lib work tb_alu
# 注意：-voptargs="+acc" 必须加，否则优化会隐藏信号，波形里看不到任何东西
# 功能：自动添加信号、设置十六进制显示、运行仿真
# =============================================================================

# 注意：不要用 wave delete all，在 ModelSim 10.7 中会报错并中止脚本

# 添加信号到波形窗口
add wave -divider "输入"
add wave -radix hex    sim:/tb_alu/op
add wave -radix hex    sim:/tb_alu/a
add wave -radix hex    sim:/tb_alu/b

add wave -divider "输出"
add wave -radix hex    sim:/tb_alu/result
add wave -radix binary sim:/tb_alu/cmp

add wave -divider "状态"
add wave -radix unsigned sim:/tb_alu/tests
add wave -radix unsigned sim:/tb_alu/errors

# 缩放波形以适应窗口
wave zoom full

# 运行仿真
run -all

# 再次缩放到完整范围
wave zoom full
