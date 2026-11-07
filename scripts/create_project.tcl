# ==============================================================================
# Script TCL: Recreate Vivado Project for RISC-V SoC INT8 Convolution Accelerator
# Target Device: AMD/Xilinx Artix-7 xc7a35tcpg236-1 (Digilent Basys 3)
# ==============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJECT_DIR [file normalize "$SCRIPT_DIR/.."]
cd $PROJECT_DIR

puts "=================================================================="
puts "  CREATING VIVADO PROJECT: SoC_RISCV.xpr"
puts "=================================================================="
create_project -force SoC_RISCV $PROJECT_DIR -part xc7a35tcpg236-1

# 1. Add all 14 RTL source files
puts "INFO: Adding RTL design files..."
add_files -norecurse [glob -nocomplain "$PROJECT_DIR/rtl/*.sv" "$PROJECT_DIR/rtl/*.v"]

# 2. Add Firmware memory initialization files
puts "INFO: Adding firmware hex..."
if {[file exists "$PROJECT_DIR/firmware/firmware.hex"]} {
    add_files -norecurse "$PROJECT_DIR/firmware/firmware.hex"
}
if {[file exists "$PROJECT_DIR/firmware.hex"]} {
    add_files -norecurse "$PROJECT_DIR/firmware.hex"
}

# 3. Add all 9 Testbenches
puts "INFO: Adding testbench files..."
add_files -fileset sim_1 -norecurse [glob -nocomplain "$PROJECT_DIR/tb/*.sv"]

# 4. Add Constraints
puts "INFO: Adding constraint files..."
if {[file exists "$PROJECT_DIR/constraints/stage7_board.xdc"]} {
    add_files -fileset constrs_1 -norecurse "$PROJECT_DIR/constraints/stage7_board.xdc"
}

# 5. Set top-level modules
set_property top fpga_top [current_fileset]
set_property top tb_soc_top [get_filesets sim_1]

# 6. Update compile orders
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "=================================================================="
puts "  PROJECT CREATED SUCCESSFULLY!"
puts "=================================================================="
