# ==============================================================================
# Script TCL: Run Synthesis & Implementation for Stage 5
# Top Module: conv_accelerator_top
# Target Part: xc7a35tcpg236-1
# ==============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJECT_DIR [file normalize "$SCRIPT_DIR/.."]
cd $PROJECT_DIR

puts "=================================================================="
puts "  MO VIVADO PROJECT: SoC_RISCV.xpr"
puts "=================================================================="
open_project SoC_RISCV.xpr

# Thiet lap Top Module cho Synthesis & Simulation
set_property top conv_accelerator_top [current_fileset]
set_property top tb_conv_accelerator_top [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Chay Synthesis
puts "=================================================================="
puts "  CHAY SYNTHESIS STAGE 5 (conv_accelerator_top)"
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
puts "  CHAY IMPLEMENTATION STAGE 5"
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
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 10 -input_pins -routable_nets -file "build/reports/stage5_timing_summary.rpt"
report_utilization -file "build/reports/stage5_utilization.rpt"
report_utilization -hierarchical -file "build/reports/stage5_utilization_hierarchical.rpt"
report_clock_utilization -file "build/reports/stage5_clock_utilization.rpt"

puts "=================================================================="
puts "  HOAN THANH BAO CAO TIMING VA UTILIZATION STAGE 5"
puts "=================================================================="
close_project
exit
