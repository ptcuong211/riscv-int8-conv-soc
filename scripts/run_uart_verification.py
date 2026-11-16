import os
import subprocess
import sys

from pathlib import Path

vivado_bin = os.environ.get("VIVADO_BIN", r"D:\vivado\2025.1\Vivado\bin")
os.environ["PATH"] = vivado_bin + os.pathsep + os.environ.get("PATH", "")

PROJECT_ROOT = Path(__file__).resolve().parents[1]
build_dir = PROJECT_ROOT / "build"
build_dir.mkdir(parents=True, exist_ok=True)
os.chdir(str(build_dir))

import shutil
shutil.copy2(PROJECT_ROOT / "firmware" / "firmware.hex", build_dir / "firmware.hex")

rtl_files = [
    "rtl/uart_tx.sv",
    "rtl/int8_multiplier.sv",
    "rtl/mac_int8.sv",
    "rtl/dot9_int8.sv",
    "rtl/ram_sync_read.sv",
    "rtl/conv_window_reader.sv",
    "rtl/conv2d_raster_scanner.sv",
    "rtl/output_buffer.sv",
    "rtl/conv_accelerator_top.sv",
    "rtl/accelerator_mmio.sv",
    "rtl/picorv32.v",
    "rtl/soc_ram.sv",
    "rtl/soc_top.sv",
    "rtl/fpga_top.sv",
    "tb/tb_fpga_top_uart.sv"
]

rtl_args = " ".join([f'"{PROJECT_ROOT / f}"' for f in rtl_files])
cmd_xvlog = f'xvlog -sv {rtl_args}'

print("--> Compiling for tb_fpga_top_uart...")
r1 = subprocess.run(cmd_xvlog, shell=True, capture_output=True, text=True)
if r1.returncode != 0:
    print("xvlog failed:\n", r1.stderr)
    print(r1.stdout)
    sys.exit(1)

cmd_xelab = 'xelab -debug typical tb_fpga_top_uart -s tb_fpga_top_uart_sim -L unisims_ver'
print("--> Elaborating tb_fpga_top_uart...")
r2 = subprocess.run(cmd_xelab, shell=True, capture_output=True, text=True)
if r2.returncode != 0:
    print("xelab failed:\n", r2.stderr)
    print(r2.stdout)
    sys.exit(1)

cmd_xsim = 'xsim tb_fpga_top_uart_sim -R'
print("--> Simulating tb_fpga_top_uart...")
r3 = subprocess.run(cmd_xsim, shell=True, capture_output=True, text=True)
print(r3.stdout)

if "ALL UART MESSAGES MATCH EXPECTED CONTENT AND ORDER 100%" in r3.stdout:
    print("\n>>> TB_FPGA_TOP_UART: TEST PASSED 100%! <<<")
    sys.exit(0)
else:
    print("\n>>> TB_FPGA_TOP_UART: TEST FAILED! <<<")
    sys.exit(1)
