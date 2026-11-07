# ==============================================================================
# Script TCL: Update Vivado Project, Run Synthesis, Implementation, Timing &
# Generate Bitstream for Stage 7 Board Bring-Up
# Target Board: Digilent Basys 3 (xc7a35tcpg236-1)
# Top Module: fpga_top
# ==============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJECT_DIR [file normalize "$SCRIPT_DIR/.."]
cd $PROJECT_DIR

puts "=================================================================="
puts "  MO VIVADO PROJECT: SoC_RISCV.xpr"
puts "=================================================================="
open_project SoC_RISCV.xpr

# Them file RTL va Firmware Stage 7
puts "INFO: Them cac file RTL Stage 7 (uart_tx.sv, fpga_top.sv) va Firmware..."
add_files -norecurse {
    rtl/uart_tx.sv
    rtl/fpga_top.sv
    firmware.hex
}
set_property file_type {Memory Initialization Files} [get_files -quiet firmware.hex]
update_compile_order -fileset sources_1

# Them file Constraints Stage 7
puts "INFO: Them Constraints Stage 7 (stage7_board.xdc)..."
add_files -fileset constrs_1 -norecurse {
    constraints/stage7_board.xdc
}

# Vo hieu hoa cac constraint cu de khong bi trung lap clock
set_property is_enabled false [get_files -of_objects [get_filesets constrs_1] *stage4_timing.xdc]
set_property is_enabled false [get_files -of_objects [get_filesets constrs_1] *stage5_timing.xdc]
set_property is_enabled false [get_files -of_objects [get_filesets constrs_1] *stage6_timing.xdc]
set_property is_enabled true  [get_files -of_objects [get_filesets constrs_1] *stage7_board.xdc]

# Thiet lap Top Module cho Synthesis
puts "INFO: Thiet lap Top Module Synthesis: fpga_top"
set_property top fpga_top [current_fileset]
update_compile_order -fileset sources_1

# Chay Synthesis
puts "=================================================================="
puts "  CHAY SYNTHESIS STAGE 7 (fpga_top)"
puts "=================================================================="
reset_run synth_1
launch_runs synth_1 -jobs 6
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: Synthesis Status: $synth_status"
if {$synth_status != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

# Chay Implementation toi buoc Generate Bitstream
puts "=================================================================="
puts "  CHAY IMPLEMENTATION & WRITE BITSTREAM STAGE 7"
puts "=================================================================="
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: Implementation Status: $impl_status"
if {$impl_status != "write_bitstream Complete!"} {
    puts "ERROR: Implementation / Bitstream generation failed!"
    exit 1
}

# Mo Design sau Implementation de trich xuat bao cao
open_run impl_1

file mkdir "build/stage7"
file mkdir "build/reports"

# Sao chep file Bitstream vao thu muc build/stage7
set bit_file [get_property DIRECTORY [get_runs impl_1]]/fpga_top.bit
if {[file exists $bit_file]} {
    file copy -force $bit_file "build/stage7/fpga_top.bit"
    puts "INFO: Da tao va luu Bitstream tai build/stage7/fpga_top.bit"
}

# Trich xuat cac bao cao
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -routable_nets -file "build/reports/stage7_timing_summary.rpt"
report_utilization -file "build/reports/stage7_utilization.rpt"
report_utilization -hierarchical -file "build/reports/stage7_utilization_hierarchical.rpt"
report_drc -file "build/reports/stage7_drc_report.rpt"
report_io -file "build/reports/stage7_io_report.rpt"

puts "=================================================================="
puts "  HOAN THANH BITSTREAM VA BAO CAO TIMING STAGE 7"
puts "=================================================================="
close_project
exit

