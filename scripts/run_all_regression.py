import os
import subprocess
import sys

vivado_bin = r"D:\vivado\2025.1\Vivado\bin"
os.environ["PATH"] = vivado_bin + os.pathsep + os.environ.get("PATH", "")

build_dir = r"D:\DA2\SoC RISCV\build"
os.makedirs(build_dir, exist_ok=True)

# Copy firmware.hex
import shutil
shutil.copy2(r"D:\DA2\SoC RISCV\firmware\firmware.hex", os.path.join(build_dir, "firmware.hex"))

tests = [
    ("1. tb_int8_multiplier", ["xvlog -sv ../rtl/int8_multiplier.sv ../tb/tb_int8_multiplier.sv",
                              "xelab -debug typical tb_int8_multiplier -s tb_int8_multiplier_sim",
                              "xsim tb_int8_multiplier_sim -R"]),
    ("2. tb_mac_int8", ["xvlog -sv ../rtl/int8_multiplier.sv ../rtl/mac_int8.sv ../tb/tb_mac_int8.sv",
                        "xelab -debug typical tb_mac_int8 -s tb_mac_int8_sim",
                        "xsim tb_mac_int8_sim -R"]),
    ("3. tb_dot9_int8", ["xvlog -sv ../rtl/int8_multiplier.sv ../rtl/mac_int8.sv ../rtl/dot9_int8.sv ../tb/tb_dot9_int8.sv",
                         "xelab -debug typical tb_dot9_int8 -s tb_dot9_int8_sim",
                         "xsim tb_dot9_int8_sim -R"]),
    ("4. tb_conv_window_reader", ["xvlog -sv ../rtl/int8_multiplier.sv ../rtl/mac_int8.sv ../rtl/dot9_int8.sv ../rtl/ram_sync_read.sv ../rtl/conv_window_reader.sv ../tb/tb_conv_window_reader.sv",
                                  "xelab -debug typical tb_conv_window_reader -s tb_conv_window_reader_sim",
                                  "xsim tb_conv_window_reader_sim -R"]),
    ("5. tb_conv2d_raster_scanner", ["xvlog -sv ../rtl/int8_multiplier.sv ../rtl/mac_int8.sv ../rtl/dot9_int8.sv ../rtl/ram_sync_read.sv ../rtl/conv_window_reader.sv ../rtl/conv2d_raster_scanner.sv ../tb/tb_conv2d_raster_scanner.sv",
                                     "xelab -debug typical tb_conv2d_raster_scanner -s tb_conv2d_raster_scanner_sim",
                                     "xsim tb_conv2d_raster_scanner_sim -R"]),
    ("6. tb_output_buffer", ["xvlog -sv ../rtl/output_buffer.sv ../tb/tb_output_buffer.sv",
                             "xelab -debug typical tb_output_buffer -s tb_output_buffer_sim",
                             "xsim tb_output_buffer_sim -R"]),
    ("7. tb_conv_accelerator_top", ["xvlog -sv ../rtl/int8_multiplier.sv ../rtl/mac_int8.sv ../rtl/dot9_int8.sv ../rtl/ram_sync_read.sv ../rtl/conv_window_reader.sv ../rtl/conv2d_raster_scanner.sv ../rtl/output_buffer.sv ../rtl/conv_accelerator_top.sv ../tb/tb_conv_accelerator_top.sv",
                                    "xelab -debug typical tb_conv_accelerator_top -s tb_conv_accelerator_top_sim",
                                    "xsim tb_conv_accelerator_top_sim -R"]),
    ("8. tb_accelerator_mmio", ["xvlog -sv ../rtl/accelerator_mmio.sv ../tb/tb_accelerator_mmio.sv",
                                "xelab -debug typical tb_accelerator_mmio -s tb_accelerator_mmio_sim",
                                "xsim tb_accelerator_mmio_sim -R"]),
    ("9. tb_soc_top", ["xvlog ../rtl/picorv32.v",
                       "xvlog -sv ../rtl/int8_multiplier.sv ../rtl/mac_int8.sv ../rtl/dot9_int8.sv ../rtl/ram_sync_read.sv ../rtl/conv_window_reader.sv ../rtl/conv2d_raster_scanner.sv ../rtl/output_buffer.sv ../rtl/conv_accelerator_top.sv ../rtl/soc_ram.sv ../rtl/accelerator_mmio.sv ../rtl/soc_top.sv ../tb/tb_soc_top.sv",
                       "xelab -debug typical tb_soc_top -s tb_soc_top_sim",
                       "xsim tb_soc_top_sim -R"])
]

passed = 0
failed = 0

for name, cmds in tests:
    print(f"\n=======================================================")
    print(f"RUNNING: {name}")
    print(f"=======================================================")
    test_ok = True
    for c in cmds:
        res = subprocess.run(c, cwd=build_dir, shell=True, capture_output=True, text=True)
        if res.returncode != 0:
            print(f"FAILED on command: {c}")
            print(res.stdout[-500:])
            print(res.stderr)
            test_ok = False
            break
        else:
            # check last line of output
            lines = [l.strip() for l in res.stdout.strip().split('\n') if l.strip()]
            if lines and "xsim" in c:
                for line in lines[-10:]:
                    print("  ", line)
    if test_ok:
        print(f"--> {name}: PASS")
        passed += 1
    else:
        print(f"--> {name}: FAIL")
        failed += 1

print("\n" + "="*60)
print(f"REGRESSION RESULTS: {passed} PASSED, {failed} FAILED out of {len(tests)}")
print("="*60)

