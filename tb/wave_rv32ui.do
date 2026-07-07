# =============================================================================
# wave_rv32ui.do — RV32I 全指令自检仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_rv32ui.do -lib work tb_rv32ui_p_all
# =============================================================================
add wave -divider "========== 时钟/复位 =========="
add wave -radix binary sim:/tb_rv32ui_p_all/clk
add wave -radix binary sim:/tb_rv32ui_p_all/rst_n

add wave -divider "========== 取指 =========="
add wave -radix hex    sim:/tb_rv32ui_p_all/pc
add wave -radix hex    sim:/tb_rv32ui_p_all/instr
add wave -radix binary sim:/tb_rv32ui_p_all/illegal

add wave -divider "========== 数据总线 =========="
add wave -radix hex    sim:/tb_rv32ui_p_all/dbus_addr
add wave -radix hex    sim:/tb_rv32ui_p_all/dbus_wdata
add wave -radix binary sim:/tb_rv32ui_p_all/dbus_read
add wave -radix binary sim:/tb_rv32ui_p_all/dbus_write
add wave -radix hex    sim:/tb_rv32ui_p_all/dbus_rdata

add wave -divider "========== CPU 内部 =========="
add wave -radix hex    sim:/tb_rv32ui_p_all/dut/if_pc
add wave -radix hex    sim:/tb_rv32ui_p_all/dut/id_instr
add wave -radix binary sim:/tb_rv32ui_p_all/dut/forward_a
add wave -radix binary sim:/tb_rv32ui_p_all/dut/forward_b
add wave -radix hex    sim:/tb_rv32ui_p_all/dut/ex_alu_result
add wave -radix hex    sim:/tb_rv32ui_p_all/dut/ex_result
add wave -radix hex    sim:/tb_rv32ui_p_all/dut/mem_wb_data
add wave -radix hex    sim:/tb_rv32ui_p_all/dut/wb_data

add wave -divider "========== 控制信号 =========="
add wave -radix binary sim:/tb_rv32ui_p_all/dut/stall
add wave -radix binary sim:/tb_rv32ui_p_all/dut/branch_taken
add wave -radix binary sim:/tb_rv32ui_p_all/dut/take_jump
add wave -radix binary sim:/tb_rv32ui_p_all/dut/flush_if_id
add wave -radix binary sim:/tb_rv32ui_p_all/dut/flush_id_ex

wave zoom full
run -all
wave zoom full
