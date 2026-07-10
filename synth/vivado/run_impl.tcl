open_project build/vivado/rvp_nexys4.xpr

# Run implementation
reset_run impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS: "

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

puts "BITSTREAM_DONE"

exit