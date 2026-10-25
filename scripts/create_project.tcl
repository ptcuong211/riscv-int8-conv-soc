cd V:/
create_project -force SoC_RISCV V:/ -part xc7a35tcpg236-1
add_files -norecurse V:/rtl/int8_multiplier.sv V:/rtl/mac_int8.sv
add_files -fileset sim_1 -norecurse V:/tb/tb_int8_multiplier.sv V:/tb/tb_mac_int8.sv
set_property top mac_int8 [current_fileset]
set_property top tb_mac_int8 [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
exit