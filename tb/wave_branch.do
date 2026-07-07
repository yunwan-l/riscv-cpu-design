# =============================================================================
# wave_branch.do — 分支判定单元仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_branch.do -lib work tb_branch_unit
# =============================================================================
add wave -divider "========== 输入 =========="
add wave -radix binary sim:/tb_branch_unit/is_branch
add wave -radix binary sim:/tb_branch_unit/cmp_result

add wave -divider "========== 输出 =========="
add wave -radix binary sim:/tb_branch_unit/branch_taken

add wave -divider "========== 状态 =========="
add wave -radix unsigned sim:/tb_branch_unit/tests
add wave -radix unsigned sim:/tb_branch_unit/errors

wave zoom full
run -all
wave zoom full
