# =============================================================================
# wave_pipeline.do — 流水线 CPU 仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_pipeline.do -lib work tb_core_pipeline
# 注意：-voptargs="+acc" 必须加，否则优化会隐藏信号，波形里看不到任何东西
# 功能：自动添加各级流水线信号、设置显示格式、运行仿真
# =============================================================================

# 注意：不要用 wave delete all，在 ModelSim 10.7 中会报错并中止脚本

# =========================================================================
# IF 级（取指）
# =========================================================================
add wave -divider "========== IF 级 (取指) =========="
add wave -radix hex    sim:/tb_core_pipeline/dut/if_pc
add wave -radix hex    sim:/tb_core_pipeline/dut/if_instr
add wave -radix hex    sim:/tb_core_pipeline/dut/if_pc_next

# =========================================================================
# ID 级（译码）
# =========================================================================
add wave -divider "========== ID 级 (译码) =========="
add wave -radix hex    sim:/tb_core_pipeline/dut/id_pc
add wave -radix hex    sim:/tb_core_pipeline/dut/id_instr
add wave -radix hex    sim:/tb_core_pipeline/dut/id_imm
add wave -radix hex    sim:/tb_core_pipeline/dut/id_rs1_data
add wave -radix hex    sim:/tb_core_pipeline/dut/id_rs2_data
add wave -radix hex    sim:/tb_core_pipeline/dut/id_rs1_fwd
add wave -radix hex    sim:/tb_core_pipeline/dut/id_rs2_fwd

# =========================================================================
# EX 级（执行）
# =========================================================================
add wave -divider "========== EX 级 (执行) =========="
add wave -radix binary sim:/tb_core_pipeline/dut/forward_a
add wave -radix binary sim:/tb_core_pipeline/dut/forward_b
add wave -radix hex    sim:/tb_core_pipeline/dut/ex_forward_a_val
add wave -radix hex    sim:/tb_core_pipeline/dut/ex_forward_b_val
add wave -radix hex    sim:/tb_core_pipeline/dut/ex_alu_op_a
add wave -radix hex    sim:/tb_core_pipeline/dut/ex_alu_op_b
add wave -radix hex    sim:/tb_core_pipeline/dut/ex_alu_result
add wave -radix hex    sim:/tb_core_pipeline/dut/ex_result

# =========================================================================
# MEM 级（访存）
# =========================================================================
add wave -divider "========== MEM 级 (访存) =========="
add wave -radix hex    sim:/tb_core_pipeline/dut/mem_alu_result
add wave -radix hex    sim:/tb_core_pipeline/dbus_addr
add wave -radix hex    sim:/tb_core_pipeline/dbus_wdata
add wave -radix binary sim:/tb_core_pipeline/dbus_read
add wave -radix binary sim:/tb_core_pipeline/dbus_write
add wave -radix hex    sim:/tb_core_pipeline/dbus_rdata
add wave -radix hex    sim:/tb_core_pipeline/dut/mem_wb_data

# =========================================================================
# WB 级（写回）
# =========================================================================
add wave -divider "========== WB 级 (写回) =========="
add wave -radix hex    sim:/tb_core_pipeline/dut/wb_data

# =========================================================================
# 控制信号
# =========================================================================
add wave -divider "========== 控制信号 =========="
add wave -radix binary sim:/tb_core_pipeline/dut/stall
add wave -radix binary sim:/tb_core_pipeline/dut/branch_taken
add wave -radix binary sim:/tb_core_pipeline/dut/take_jump
add wave -radix binary sim:/tb_core_pipeline/dut/flush_if_id
add wave -radix binary sim:/tb_core_pipeline/dut/flush_id_ex

# =========================================================================
# 时钟和复位
# =========================================================================
add wave -divider "========== 时钟/复位 =========="
add wave -radix binary sim:/tb_core_pipeline/clk
add wave -radix binary sim:/tb_core_pipeline/rst_n

# 缩放波形以适应窗口
wave zoom full

# 运行仿真
run -all

# 再次缩放到完整范围
wave zoom full
