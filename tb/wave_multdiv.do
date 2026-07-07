# =============================================================================
# wave_multdiv.do — M 扩展乘除法仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_multdiv.do -lib work tb_multdiv
# =============================================================================
add wave -divider "========== 输入 =========="
add wave -radix symbolic sim:/tb_multdiv/op
add wave -radix hex      sim:/tb_multdiv/a
add wave -radix hex      sim:/tb_multdiv/b

add wave -divider "========== 输出 =========="
add wave -radix hex      sim:/tb_multdiv/result

add wave -divider "========== 状态 =========="
add wave -radix unsigned sim:/tb_multdiv/tests
add wave -radix unsigned sim:/tb_multdiv/errors

wave zoom full
run -all
wave zoom full
