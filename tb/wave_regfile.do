# =============================================================================
# wave_regfile.do — 寄存器堆仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_regfile.do -lib work tb_register_file
# 注意：-voptargs="+acc" 必须加，否则优化会隐藏信号，波形里看不到任何东西
# 功能：自动添加寄存器堆接口信号 + 内部 regs 数组、运行仿真
# =============================================================================

# =========================================================================
# 时钟和复位
# =========================================================================
add wave -divider "========== 时钟/复位 =========="
add wave -radix binary   sim:/tb_register_file/clk
add wave -radix binary   sim:/tb_register_file/rst_n

# =========================================================================
# 写端口
# =========================================================================
add wave -divider "========== 写端口 =========="
add wave -radix binary   sim:/tb_register_file/we
add wave -radix unsigned sim:/tb_register_file/waddr
add wave -radix hex      sim:/tb_register_file/wdata

# =========================================================================
# 读端口 1
# =========================================================================
add wave -divider "========== 读端口 1 =========="
add wave -radix unsigned sim:/tb_register_file/raddr1
add wave -radix hex      sim:/tb_register_file/rdata1

# =========================================================================
# 读端口 2
# =========================================================================
add wave -divider "========== 读端口 2 =========="
add wave -radix unsigned sim:/tb_register_file/raddr2
add wave -radix hex      sim:/tb_register_file/rdata2

# =========================================================================
# 内部寄存器堆数组（观察 32 个寄存器的值变化）
# =========================================================================
add wave -divider "========== 内部寄存器堆 regs 0-7 =========="
add wave -radix hex      sim:/tb_register_file/dut/regs(0)
add wave -radix hex      sim:/tb_register_file/dut/regs(1)
add wave -radix hex      sim:/tb_register_file/dut/regs(2)
add wave -radix hex      sim:/tb_register_file/dut/regs(3)
add wave -radix hex      sim:/tb_register_file/dut/regs(4)
add wave -radix hex      sim:/tb_register_file/dut/regs(5)
add wave -radix hex      sim:/tb_register_file/dut/regs(6)
add wave -radix hex      sim:/tb_register_file/dut/regs(7)

# =========================================================================
# 测试状态
# =========================================================================
add wave -divider "========== 测试状态 =========="
add wave -radix unsigned sim:/tb_register_file/tests
add wave -radix unsigned sim:/tb_register_file/errors

# 缩放波形以适应窗口
wave zoom full

# 运行仿真
run -all

# 再次缩放到完整范围
wave zoom full
