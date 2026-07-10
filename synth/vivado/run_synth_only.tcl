open_project build/vivado/rvp_nexys4.xpr

# Create synth run directory and copy firmware
file mkdir build/vivado/rvp_nexys4.runs/synth_1
file copy -force synth/vivado/firmware.hex build/vivado/rvp_nexys4.runs/synth_1/firmware.hex
puts "Firmware copied to synth_1 directory"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS: "

# Report basic results
set util_rpt "build/vivado/rvp_nexys4.runs/synth_1/rvp_fpga_top_utilization_synth.rpt"
if {[file exists ]} {
    puts "=== Utilization Report Found ==="
}

exit