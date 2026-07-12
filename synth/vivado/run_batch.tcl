## =============================================================================
## run_batch.tcl - 批量综合所有测试固件，生成各自命名的bit文件
## =============================================================================
## 用法: vivado -mode batch -source run_batch.tcl
## 输出: build/vivado/bitstreams/test_<name>.bit
## =============================================================================

set script_dir   [file dirname [info script]]
set project_root [file normalize [file join $script_dir .. ..]]
set out_dir      [file join $project_root "build" "vivado" "bitstreams"]
file mkdir $out_dir

# 测试固件列表
set tests {
    test_loop
    test_sequential
    test_branchy
    test_mixed
    test_large
    test_thrash
}

puts "============================================================================="
puts " Batch Synthesis: [llength $tests] tests"
puts "============================================================================="

set_msg_config -id {Synth 8-3331} -suppress

foreach test_name $tests {
    puts "\n============================================================================="
    puts " Building: $test_name"
    puts "============================================================================="

    # 1. 复制固件
    set hex_src [file join $project_root "board" "${test_name}.hex"]
    if {![file exists $hex_src]} {
        puts "ERROR: $hex_src not found, skipping."
        continue
    }
    file copy -force $hex_src [file join $project_root "rtl" "core" "firmware.hex"]
    puts "  Firmware: ${test_name}.hex"

    # 2. 创建工程（每次重新创建，避免状态残留）
    if {[catch {close_project} err]} { }
    create_project -in_memory -part xc7a100tcsg324-1
    set_property default_lib xil_defaultlib [current_project]
    set_property target_language Verilog [current_project]
    set_property include_dirs [list \
        [file join $project_root "config"] \
        [file join $project_root "synth" "vivado"] \
    ] [current_fileset]
    set_property verilog_define {RVP_RV32E=0 RVP_RV32M=1 RVP_RV32C=0 RVP_ICacheEnable=0 RVP_DCacheEnable=0 RVP_ICacheReplacePolicy=0 RVP_DCacheReplacePolicy=0 RVP_Forwarding=0 RVP_BranchPredict=0 RVP_CacheStatsEnable=0} [current_fileset]

    # 3. 读取源文件
    read_verilog -sv [list \
        [file join $project_root "rtl" "rvp_pkg.sv"] \
        [file join $project_root "rtl" "core" "rvp_alu.sv"] \
        [file join $project_root "rtl" "core" "rvp_branch_unit.sv"] \
        [file join $project_root "rtl" "core" "rvp_core_pipeline.sv"] \
        [file join $project_root "rtl" "core" "rvp_data_mem.sv"] \
        [file join $project_root "rtl" "core" "rvp_decoder.sv"] \
        [file join $project_root "rtl" "core" "rvp_forward_unit.sv"] \
        [file join $project_root "rtl" "periph" "rvp_gpio.sv"] \
        [file join $project_root "rtl" "core" "rvp_hazard_unit.sv"] \
        [file join $project_root "rtl" "cache" "rvp_icache_pmru8.sv"] \
        [file join $project_root "rtl" "core" "rvp_imm_generator.sv"] \
        [file join $project_root "rtl" "core" "rvp_instr_mem.sv"] \
        [file join $project_root "rtl" "core" "rvp_multdiv.sv"] \
        [file join $project_root "rtl" "core" "rvp_pipeline_regs.sv"] \
        [file join $project_root "rtl" "core" "rvp_register_file.sv"] \
        [file join $project_root "rtl" "rvp_soc.sv"] \
        [file join $project_root "rtl" "periph" "rvp_timer.sv"] \
        [file join $project_root "rtl" "periph" "rvp_uart.sv"] \
        [file join $project_root "rtl" "rvp_fpga_top.sv"] \
    ]

    # 4. 读取XDC
    read_xdc [file join $script_dir "rvp_nexys4.xdc"]

    # 5. 综合
    puts "  Synthesizing..."
    set synth_err [catch {synth_design -top rvp_fpga_top -part xc7a100tcsg324-1 -flatten_hierarchy none} synth_result]
    if {$synth_err} {
        puts "  WARNING: synth_design error, checking if design exists..."
        if {[catch {get_designs rvp_fpga_top}]} {
            puts "  ERROR: Design not in memory, skipping $test_name"
            continue
        }
    }

    # 6. 实现
    puts "  Placing..."
    catch {opt_design}
    catch {place_design}
    puts "  Routing..."
    catch {phys_opt_design}
    catch {route_design}

    # 7. 时序检查
    set wns [catch {get_property SLACK_MIN [get_timing_paths -npaths 1 -max_paths_slow]} wns_val]
    if {!$wns} {
        puts "  WNS: $wns_val ns"
    }

    # 8. 生成bit文件
    puts "  Generating bitstream..."
    catch {write_bitstream -force [file join $out_dir "${test_name}.bit"]}

    # 9. 复制到 build/vivado/ 也放一份
    file copy -force [file join $out_dir "${test_name}.bit"] [file join $project_root "build" "vivado" "${test_name}.bit"]

    puts "  DONE: ${test_name}.bit"

    # 10. 清理
    file delete -force [file join $project_root "rtl" "core" "firmware.hex"]
}

puts "\n============================================================================="
puts " Batch synthesis complete!"
puts " Output directory: $out_dir"
puts "============================================================================="

# 列出生成的文件
puts "\nGenerated bit files:"
foreach test_name $tests {
    set bitfile [file join $out_dir "${test_name}.bit"]
    if {[file exists $bitfile]} {
        set sz [file size $bitfile]
        set mt [file mtime $bitfile]
        puts "  ${test_name}.bit  (${sz} bytes, [clock format $mt -format {%Y-%m-%d %H:%M}])"
    } else {
        puts "  ${test_name}.bit  MISSING"
    }
}
