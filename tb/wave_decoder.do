# =============================================================================
# wave_decoder.do — 译码器仿真波形自动配置脚本
# =============================================================================
# 用法：vsim -voptargs="+acc" -do wave_decoder.do -lib work tb_decoder
# =============================================================================
add wave -divider "========== 输入 =========="
add wave -radix hex      sim:/tb_decoder/instr

add wave -divider "========== 译码输出 ctrl =========="
add wave -radix unsigned sim:/tb_decoder/ctrl.rs1_addr
add wave -radix unsigned sim:/tb_decoder/ctrl.rs2_addr
add wave -radix unsigned sim:/tb_decoder/ctrl.rd_addr
add wave -radix symbolic sim:/tb_decoder/ctrl.alu_op
add wave -radix binary   sim:/tb_decoder/ctrl.alu_op_a_sel
add wave -radix binary   sim:/tb_decoder/ctrl.alu_op_b_sel
add wave -radix binary   sim:/tb_decoder/ctrl.use_multdiv
add wave -radix symbolic sim:/tb_decoder/ctrl.multdiv_op
add wave -radix symbolic sim:/tb_decoder/ctrl.imm_type
add wave -radix binary   sim:/tb_decoder/ctrl.reg_write
add wave -radix symbolic sim:/tb_decoder/ctrl.wb_sel
add wave -radix binary   sim:/tb_decoder/ctrl.mem_read
add wave -radix binary   sim:/tb_decoder/ctrl.mem_write
add wave -radix symbolic sim:/tb_decoder/ctrl.mem_size
add wave -radix binary   sim:/tb_decoder/ctrl.mem_unsigned
add wave -radix symbolic sim:/tb_decoder/ctrl.next_pc
add wave -radix binary   sim:/tb_decoder/ctrl.branch
add wave -radix binary   sim:/tb_decoder/ctrl.illegal

add wave -divider "========== 状态 =========="
add wave -radix unsigned sim:/tb_decoder/tests
add wave -radix unsigned sim:/tb_decoder/errors

wave zoom full
run -all
wave zoom full
