# =============================================================================
# wave_soc.do — SoC 系统集成仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_soc.do -lib work tb_soc
# 注意：-voptargs="+acc" 必须加，否则优化会隐藏信号，波形里看不到任何东西
# 功能：自动添加 SoC 各外设接口信号、运行仿真
# =============================================================================

# 注意：不要用 wave delete all，在 ModelSim 10.7 中会报错并中止脚本

# =========================================================================
# 顶层信号
# =========================================================================
add wave -divider "========== 时钟/复位 =========="
add wave -radix binary   sim:/tb_soc/clk
add wave -radix binary   sim:/tb_soc/rst_n

add wave -divider "========== CPU 调试 =========="
add wave -radix hex      sim:/tb_soc/pc_dbg

# =========================================================================
# GPIO 接口
# =========================================================================
add wave -divider "========== GPIO =========="
add wave -radix hex      sim:/tb_soc/sw
add wave -radix hex      sim:/tb_soc/led

# =========================================================================
# UART 接口
# =========================================================================
add wave -divider "========== UART =========="
add wave -radix binary   sim:/tb_soc/uart_tx

# =========================================================================
# SoC 内部总线信号
# =========================================================================
add wave -divider "========== 总线 =========="
add wave -radix hex      sim:/tb_soc/dut/dbus_addr
add wave -radix hex      sim:/tb_soc/dut/dbus_wdata
add wave -radix binary   sim:/tb_soc/dut/dbus_read
add wave -radix binary   sim:/tb_soc/dut/dbus_write
add wave -radix hex      sim:/tb_soc/dut/dbus_rdata

# =========================================================================
# 外设内部状态
# =========================================================================
add wave -divider "========== GPIO 内部 =========="
add wave -radix hex      sim:/tb_soc/dut/gpio/output_reg

add wave -divider "========== Timer 内部 =========="
add wave -radix hex      sim:/tb_soc/dut/timer/count
add wave -radix binary   sim:/tb_soc/dut/timer/enable

add wave -divider "========== UART 内部 =========="
add wave -radix hex      sim:/tb_soc/dut/uart/tx_shift
add wave -radix binary   sim:/tb_soc/dut/uart/tx_busy

add wave -divider "========== 状态 =========="
add wave -radix unsigned sim:/tb_soc/tests
add wave -radix unsigned sim:/tb_soc/errors

# 缩放波形以适应窗口
wave zoom full

# 运行仿真
run -all

# 再次缩放到完整范围
wave zoom full
