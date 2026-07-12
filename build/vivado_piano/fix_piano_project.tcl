# ============================================================
# fix_piano_project.tcl
# 在 Vivado Tcl Console 中执行: source C:/rvp_proj/build/vivado_piano/fix_piano_project.tcl
# 功能: 将 Piano 项目的 I-Cache 从 rvp_icache.sv 替换为 rvp_icache_pmru8.sv
#       并启用 rvp_instr_mem.sv（rvp_icache_pmru8 的依赖）
# ============================================================

puts "========== 修复 Piano 项目文件列表 =========="

# 1. 移除旧的 rvp_icache.sv（2-way，接口不兼容）
set old_icache [get_files */rvp_icache.sv]
if {$old_icache ne ""} {
    remove_files $old_icache
    puts "\[OK\] 移除 rvp_icache.sv"
} else {
    puts "\[SKIP\] rvp_icache.sv 不存在"
}

# 2. 添加 rvp_icache_pmru8.sv（8-way，rvp_core_pipeline 实例化的模块）
set new_icache [get_files */rvp_icache_pmru8.sv]
if {$new_icache eq ""} {
    add_files -norecurse {C:/rvp_proj/rtl/cache/rvp_icache_pmru8.sv}
    puts "\[OK\] 添加 rvp_icache_pmru8.sv"
} else {
    puts "\[SKIP\] rvp_icache_pmru8.sv 已存在"
}

# 3. 确保 rvp_instr_mem.sv 被启用（rvp_icache_pmru8 的依赖）
#    如果已被 AutoDisabled，remove 后重新 add 即可启用
set instr_mem [get_files */rvp_instr_mem.sv]
if {$instr_mem ne ""} {
    remove_files $instr_mem
    puts "\[OK\] 移除 rvp_instr_mem.sv (准备重新启用)"
}
add_files -norecurse {C:/rvp_proj/rtl/core/rvp_instr_mem.sv}
puts "\[OK\] 添加 rvp_instr_mem.sv"

# 4. 更新编译顺序
update_compile_order -fileset sources_1
puts "\[OK\] 更新编译顺序"

# 5. 打印当前文件列表确认
puts ""
puts "========== 当前源文件列表 =========="
foreach f [get_files] {
    puts "  $f"
}

puts ""
puts "========== 修复完成 =========="
puts "下一步: reset_run synth_1 && launch_runs synth_1"
