open_project my_uart_oled_dht11.xpr
update_compile_order -fileset sources_1
synth_design -top top -part xc7a35tcpg236-1
report_timing_summary -file sim/vivado_synth_timing.rpt
exit
