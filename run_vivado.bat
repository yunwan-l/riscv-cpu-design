call "C:\Xilinx\Vivado\2018.3\settings64.bat"
cd /d d:\cache-riscv-cpu-design
vivado -mode batch -source synth/vivado/run_overflow.tcl -log build/vivado/overflow_build2.log -journal build/vivado/overflow_build2.jou
