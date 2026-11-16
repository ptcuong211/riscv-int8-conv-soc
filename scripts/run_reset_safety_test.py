import os
import subprocess
import sys

vivado_bin = r"D:\vivado\2025.1\Vivado\bin"
os.environ["PATH"] = vivado_bin + os.pathsep + os.environ.get("PATH", "")

repo_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
build_dir = os.path.join(repo_dir, "build")
os.makedirs(build_dir, exist_ok=True)
os.chdir(build_dir)

print("=" * 70)
print("  RUNNING F-01 DIRECTED RESET SAFETY VERIFICATION (10 CHECKS)")
print("=" * 70)

soc_ram_sv = os.path.join(repo_dir, "rtl", "soc_ram.sv")
tb_safety_sv = os.path.join(repo_dir, "tb", "tb_soc_ram_2ff_safety.sv")

cmd_compile = f'xvlog -sv "{soc_ram_sv}" "{tb_safety_sv}"'
print(f"--> Compiling: {cmd_compile}")
r1 = subprocess.run(cmd_compile, shell=True, capture_output=True, text=True)
if r1.returncode != 0:
    print("Compilation failed:\n", r1.stderr)
    sys.exit(1)

cmd_elab = 'xelab -debug typical tb_soc_ram_2ff_safety -s tb_soc_ram_2ff_safety_sim'
print(f"--> Elaborating: {cmd_elab}")
r2 = subprocess.run(cmd_elab, shell=True, capture_output=True, text=True)
if r2.returncode != 0:
    print("Elaboration failed:\n", r2.stderr)
    sys.exit(1)

cmd_sim = 'xsim tb_soc_ram_2ff_safety_sim -R'
print(f"--> Simulating: {cmd_sim}")
r3 = subprocess.run(cmd_sim, shell=True, capture_output=True, text=True)
print(r3.stdout)

if "ALL 10 PHASE 3F RESET SAFETY TESTS PASSED" in r3.stdout:
    print("=" * 70)
    print(">>> VERIFICATION RESULT: 10/10 RESET SAFETY TESTS PASSED! <<<")
    print("=" * 70)
    sys.exit(0)
else:
    print("Verification failed!")
    sys.exit(1)
