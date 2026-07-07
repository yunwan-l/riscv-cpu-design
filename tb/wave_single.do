# =============================================================================
# wave_single.do — 单周期 CPU 仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_single.do -lib work tb_core_single
# 注意：-voptargs="+acc" 必须加，否则优化会隐藏信号，波形里看不到任何东西
# 功能：自动添加 CPU 关键信号、运行仿真
# =============================================================================

# 注意：不要用 wave delete all，在 ModelSim 10.7 中会报错并中止脚本

# =========================================================================
# 顶层信号
# =========================================================================
add wave -divider "========== 时钟/复位 =========="
add wave -radix binary   sim:/tb_core_single/clk
add wave -radix binary   sim:/tb_core_single/rst_n

add wave -divider "========== 取指 =========="
add wave -radix hex      sim:/tb_core_single/pc
add wave -radix hex      sim:/tb_core_single/instr
add wave -radix binary   sim:/tb_core_single/illegal

# =========================================================================
# DUT 内部信号（CPU 核心）
# =========================================================================
add wave -divider "========== 寄存器堆 =========="
add wave -radix hex      sim:/tb_core_single/dut/reg_file/regs(1)
add wave -radix hex      sim:/tb_core_single/dut/reg_file/regs(2)
add wave -radix hex      sim:/tb_core_single/dut/reg_file/regs(3)
add wave -radix hex      sim:/tb_core_single/dut/reg_file/regs(4)
add wave -radix hex      sim:/tb_core_single/dut/reg_file/regs(5)
add wave -radix hex      sim:/tb_core_single/dut/reg_file/regs(6)
add wave -radix hex      sim:/tb_core_single/dut/reg_file/regs(7)

add wave -divider "========== 译码 =========="
add wave -radix hex      sim:/tb_core_single/dut/imm
add wave -radix hex      sim:/tb_core_single/dut/rs1_data
add wave -radix hex      sim:/tb_core_single/dut/rs2_data

add wave -divider "========== 执行 =========="
add wave -radix hex      sim:/tb_core_single/dut/alu_result
add wave -radix hex      sim:/tb_core_single/dut/ex_result

add wave -divider "========== 访存 =========="
add wave -radix hex      sim:/tb_core_single/dut/mem_rdata

add wave -divider "========== 状态 =========="
add wave -radix unsigned sim:/tb_core_single/tests
add wave -radix unsigned sim:/tb_core_single/errors

# 缩放波形以适应窗口
wave zoom full

# 运行仿真
run -all

# 再次缩放到完整范围
wave zoom full
