# =============================================================================
# wave_imm.do — 立即数生成器仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_imm.do -lib work tb_imm_generator
# =============================================================================
add wave -divider "========== 输入 =========="
add wave -radix hex      sim:/tb_imm_generator/instr
add wave -radix symbolic sim:/tb_imm_generator/imm_type

add wave -divider "========== 输出 =========="
add wave -radix hex      sim:/tb_imm_generator/imm

add wave -divider "========== 状态 =========="
add wave -radix unsigned sim:/tb_imm_generator/tests
add wave -radix unsigned sim:/tb_imm_generator/errors

wave zoom full
run -all
wave zoom full
