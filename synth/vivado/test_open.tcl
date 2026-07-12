# test_open.tcl — 最小测试：能否打开工程
open_project D:/cache-riscv-cpu-design/build/vivado/rvp_nexys4.xpr
puts "Project opened successfully"
puts "Runs: [get_runs *]"
close_project
puts "Done"
