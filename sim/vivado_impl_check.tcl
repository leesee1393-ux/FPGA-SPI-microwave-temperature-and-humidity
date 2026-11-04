open_project my_uart_oled_dht11.xpr
update_compile_order -fileset sources_1
synth_design -top top -part xc7a35tcpg236-1
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file sim/vivado_impl_timing.rpt
report_drc -file sim/vivado_impl_drc.rpt
write_bitstream -force sim/top_checked.bit
exit
