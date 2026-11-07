# ==============================================================================
# Script TCL: Update Vivado Project, Run Synthesis & Implementation for Stage 6
# Top Module: soc_top
# Target Part: xc7a35tcpg236-1
# ==============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJECT_DIR [file normalize "$SCRIPT_DIR/.."]
cd $PROJECT_DIR

puts "=================================================================="
puts "  MO VIVADO PROJECT: SoC_RISCV.xpr"
puts "=================================================================="
open_project SoC_RISCV.xpr

# Them file RTL moi vao project neu chua co
puts "INFO: Them cac file RTL Stage 6..."
add_files -norecurse {
    rtl/picorv32.v
    rtl/soc_ram.sv
    rtl/accelerator_mmio.sv
    rtl/soc_top.sv
}
update_compile_order -fileset sources_1

# Them file Simulation moi vao project
puts "INFO: Them cac file Simulation Stage 6..."
add_files -fileset sim_1 -norecurse {
    tb/tb_accelerator_mmio.sv
    tb/tb_soc_top.sv
}
update_compile_order -fileset sim_1

# Them file Constraints Stage 6
puts "INFO: Them Constraints Stage 6..."
add_files -fileset constrs_1 -norecurse {
    constraints/stage6_timing.xdc
}

# Vo hieu hoa cac constraint cu de tranh trung lap clk
set_property is_enabled false [get_files -of_objects [get_filesets constrs_1] *stage4_timing.xdc]
set_property is_enabled false [get_files -of_objects [get_filesets constrs_1] *stage5_timing.xdc]
set_property is_enabled true  [get_files -of_objects [get_filesets constrs_1] *stage6_timing.xdc]

# Thiet lap Top Module cho Synthesis & Simulation
puts "INFO: Thiet lap Top Module: soc_top"
set_property top soc_top [current_fileset]
set_property top tb_soc_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Chay Synthesis
puts "=================================================================="
puts "  CHAY SYNTHESIS STAGE 6 (soc_top)"
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

# Chay Implementation
puts "=================================================================="
puts "  CHAY IMPLEMENTATION STAGE 6"
puts "=================================================================="
reset_run impl_1
launch_runs impl_1 -jobs 6
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: Implementation Status: $impl_status"
if {$impl_status != "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

# Mo Design sau Implementation de trich xuat bao cao
open_run impl_1

file mkdir "build/reports"
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -routable_nets -file "build/reports/stage6_timing_summary.rpt"
report_utilization -file "build/reports/stage6_utilization.rpt"
report_utilization -hierarchical -file "build/reports/stage6_utilization_hierarchical.rpt"
report_clock_utilization -file "build/reports/stage6_clock_utilization.rpt"

puts "=================================================================="
puts "  HOAN THANH BAO CAO TIMING VA UTILIZATION STAGE 6"
puts "=================================================================="
close_project
exit

