# RISC-V SoC with Dedicated Signed INT8 2D Convolution Hardware Accelerator on FPGA

[![RTL Verification](https://img.shields.io/badge/Verification-9%2F9%20Testbenches%20PASS-brightgreen.svg)]()
[![FPGA Implementation](https://img.shields.io/badge/Implementation-Artix--7%20xc7a35t-blue.svg)]()
[![Clock Frequency](https://img.shields.io/badge/Timing-100%20MHz%20MET%20(WNS%20%2B0.255ns)-success.svg)]()
[![Bitstream Status](https://img.shields.io/badge/Bitstream-Generated%20(PASS%20TO%20BITSTREAM)-orange.svg)]()
[![Hardware Test](https://img.shields.io/badge/Board%20Bring--Up-Hardware%20Test%20Pending-yellow.svg)]()

> **Project Title:** Design and RTL Implementation of a RISC-V SoC Integrated with a Dedicated Hardware Accelerator for Signed INT8 2D Convolution on FPGA  
> **Target FPGA Board:** Digilent Basys 3 (AMD/Xilinx Artix-7 `xc7a35tcpg236-1`)  
> **EDA Tool:** AMD Vivado Design Suite 2025.1  
> **Status:** `RTL Verified / Implementation Complete / Bitstream Generated / Hardware Test Pending`

---

## 1. Project Overview

This repository contains the complete SystemVerilog/Verilog RTL design, verification testbenches, firmware toolchain, and FPGA implementation scripts for a System-on-Chip (SoC) based on the open-source **PicoRV32 (RV32I)** RISC-V CPU core. The SoC integrates a custom, high-throughput hardware accelerator dedicated to **2D Convolution** on signed 8-bit integer (`signed INT8`) data, operating on single-channel feature maps for lightweight edge convolutional neural network (CNN) workloads.

### Key Specifications
- **Input Feature Map:** Single-channel $32 \times 32$ matrix (1,024 elements), two's complement signed INT8 $[-128, +127]$.
- **Convolution Kernel:** $3 \times 3$ kernel (9 elements), signed INT8, Stride = 1, Padding = 0.
- **Output Feature Map:** $30 \times 30$ matrix ($900$ elements), signed INT32 $[-147,456 \text{ to } +147,456]$ stored in 32-bit registers to mathematically prevent accumulator overflow.
- **Clock Frequency:** 100.00 MHz ($T_{\text{clk}} = 10.000\text{ ns}$).
- **Interconnect:** Custom Memory-Mapped I/O (MMIO) controller interfacing PicoRV32 Native Memory Bus.
- **Board Peripherals:** 2-stage Flip-Flop AASD reset synchronizer, status LEDs, and UART transmitter (115200 baud, 8-N-1) for host communication.

---

## 2. SoC System Architecture

```
+--------------------------------------------------------------------------------------------------+
|                                      FPGA TOP-LEVEL (fpga_top)                                   |
|                                                                                                  |
|   +-------------------+    100 MHz sys_clk      +--------------------------------------------+   |
|   | 100 MHz Oscillator|------------------------>| Two-Stage FF Asynchronous Assertion        |   |
|   +-------------------+                         | Synchronous Deassertion (AASD) Reset Sync  |   |
|   | Button btnC (U18) |------------------------>+--------------------------------------------+   |
|   +-------------------+                                               |                          |
|                                                                    rst_n                         |
|   +-------------------------------------------------------------------|----------------------+   |
|   |                            SoC TOP-LEVEL (soc_top)                v                      |   |
|   |                                                                                          |   |
|   |   +-------------------+               PicoRV32 Native Memory Bus                         |   |
|   |   |   PicoRV32 CPU    |<========================================+                        |   |
|   |   |  (RV32I Core)     |                                         |                        |   |
|   |   +-------------------+                                         |                        |   |
|   |                                                                 v                        |   |
|   |   +----------------------------------------------------------------------------------+   |   |
|   |   |                     Address Decoder & Interconnect Controller                    |   |   |
|   |   +----------------------------------------------------------------------------------+   |   |
|   |             | (0x0000_0000 - 0x0FFF_FFFF)             | (0x1000_0000 - 0x1FFF_FFFF)      |   |
|   |             v                                         v                                  |   |
|   |   +-------------------------+             +--------------------------------------+       |   |
|   |   |       16 KB RAM         |             |       MMIO Control Interface         |       |   |
|   |   | (4x RAMB36E1 BRAMs)     |             |      (accelerator_mmio.sv)           |       |   |
|   |   | Holds Firmware & Data   |             +--------------------------------------+       |   |
|   |   +-------------------------+                                 |                          |   |
|   |                                                               v                          |   |
|   |   +----------------------------------------------------------------------------------+   |   |
|   |   |              CONVOLUTION ACCELERATOR SUBSYSTEM (conv_accelerator_top)            |   |   |
|   |   |                                                                                  |   |   |
|   |   |   +-----------------------+              +-----------------------------------+   |   |   |
|   |   |   |  Input Buffer (BRAM)  |              |        Weight Buffer (Dist-RAM)   |   |   |   |
|   |   |   | 1,024 x 8-bit (1 KB)  |              |          9 x 8-bit (9 Bytes)      |   |   |   |
|   |   |   +-----------------------+              +-----------------------------------+   |   |   |
|   |   |               |                                            |                     |   |   |
|   |   |               v                                            v                     |   |   |
|   |   |   +--------------------------------------------------------------------------+   |   |   |
|   |   |   |             2D Raster Scanner (conv2d_raster_scanner.sv)                 |   |   |   |
|   |   |   |  - Iterates 30x30 output windows (row: 0..29, col: 0..29)                |   |   |   |
|   |   |   |  - Generates linear pixel addresses addr = (row + dr)*32 + (col + dc)    |   |   |   |
|   |   |   +--------------------------------------------------------------------------+   |   |   |
|   |   |                                       |                                          |   |   |
|   |   |                                       v Valid/Ready                              |   |   |
|   |   |   +--------------------------------------------------------------------------+   |   |   |
|   |   |   |             Dot9 Sequential MAC Compute Engine (dot9_int8.sv)            |   |   |   |
|   |   |   |  - int8_multiplier.sv (Combinational 8x8 signed -> 16-bit)              |   |   |   |
|   |   |   |  - mac_int8.sv        (Accumulator 32-bit with Sign Extension)           |   |   |   |
|   |   |   |  - 11-cycle execution per 3x3 window                                     |   |   |   |
|   |   |   +--------------------------------------------------------------------------+   |   |   |
|   |   |                                       |                                          |   |   |
|   |   |                                       v 32-bit INT32                             |   |   |
|   |   |   +--------------------------------------------------------------------------+   |   |   |
|   |   |   |               Output Buffer Subsystem (output_buffer.sv)                 |   |   |   |
|   |   |   |  - 900 x 32-bit INT32 Dual-Port RAM (Dual RAMB36E1, 3.6 KB)              |   |   |   |
|   |   |   +--------------------------------------------------------------------------+   |   |   |
|   |   +----------------------------------------------------------------------------------+   |   |
|   +------------------------------------------------------------------------------------------+   |
|                                     |                                                            |
|                                     v                                                            |
|   +---------------------------------------------------+    UART Serial Out (115200 baud)         |
|   | UART Transmitter Module (uart_tx.sv)              |-----------------------------------> A18  |
|   +---------------------------------------------------+                                          |
|   | Status LEDs (LED[1:0] -> DONE / BUSY)             |-----------------------------------> Board|
+--------------------------------------------------------------------------------------------------+
```

---

## 3. RTL Module Hierarchy & Source Inventory

The hardware architecture comprises **14 modular Verilog/SystemVerilog source files**:

| # | Module Name | Source File | Function & Microarchitectural Description |
|---|---|---|---|
| 1 | `int8_multiplier` | [`rtl/int8_multiplier.sv`](rtl/int8_multiplier.sv) | Combinational signed 8-bit multiplier ($8 \times 8 \to 16\text{-bit}$). |
| 2 | `mac_int8` | [`rtl/mac_int8.sv`](rtl/mac_int8.sv) | Multiply-Accumulate unit with 32-bit accumulator and sign-extension. |
| 3 | `dot9_int8` | [`rtl/dot9_int8.sv`](rtl/dot9_int8.sv) | 5-state FSM sequencer performing 9 MAC operations in 11 clock cycles. |
| 4 | `ram_sync_read` | [`rtl/ram_sync_read.sv`](rtl/ram_sync_read.sv) | Synchronous on-chip BRAM buffer with strict 1-cycle read latency. |
| 5 | `conv_window_reader` | [`rtl/conv_window_reader.sv`](rtl/conv_window_reader.sv) | $3 \times 3$ window operand extractor with zero-multiplier address generator. |
| 6 | `conv2d_raster_scanner`| [`rtl/conv2d_raster_scanner.sv`](rtl/conv2d_raster_scanner.sv) | Full-frame 2D raster scanner producing 900 spatial window coordinates. |
| 7 | `output_buffer` | [`rtl/output_buffer.sv`](rtl/output_buffer.sv) | $900 \times 32\text{-bit}$ dual-port storage buffer with address decoding. |
| 8 | `conv_accelerator_top` | [`rtl/conv_accelerator_top.sv`](rtl/conv_accelerator_top.sv) | Top-level integration of the 2D convolution accelerator core. |
| 9 | `picorv32` | [`rtl/picorv32.v`](rtl/picorv32.v) | Claire Wolf's RV32I multi-cycle RISC-V open-source CPU core. |
| 10 | `soc_ram` | [`rtl/soc_ram.sv`](rtl/soc_ram.sv) | 16 KB unified program & data memory (inferred as 4 $\times$ RAMB36E1). |
| 11 | `accelerator_mmio` | [`rtl/accelerator_mmio.sv`](rtl/accelerator_mmio.sv) | MMIO slave decoder interfacing CPU native memory bus to accelerator. |
| 12 | `soc_top` | [`rtl/soc_top.sv`](rtl/soc_top.sv) | Complete SoC top-level integrating CPU, RAM, MMIO, and Accelerator. |
| 13 | `uart_tx` | [`rtl/uart_tx.sv`](rtl/uart_tx.sv) | Serial transmitter (115200 baud, 8-N-1) for status logging to host PC. |
| 14 | `fpga_top` | [`rtl/fpga_top.sv`](rtl/fpga_top.sv) | FPGA top wrapper with 2-stage FF AASD reset synchronizer & I/O pins. |

---

## 4. Memory-Mapped I/O (MMIO) Register Map

The accelerator registers and buffers are mapped to base address `0x1000_0000`:

| Register Name | Offset Address | Access | Bit Width | Description |
|---|---|:---:|:---:|---|
| `REG_ACCEL_CTRL` | `0x1000_0000` | R/W | 32 | Control: Bit [0] = `START` (pulse/auto-clear), Bit [1] = `SOFT_RESET`. |
| `REG_ACCEL_STATUS` | `0x1000_0004` | R/W1C | 32 | Status: Bit [0] = `BUSY`, Bit [1] = `DONE` (Write-1-to-Clear sticky flag). |
| `REG_ACCEL_WINDOW_COUNT`| `0x1000_0008` | RO | 32 | Number of completed windows (ranges 0 to 900). |
| `REG_IBUF_ADDR` | `0x1000_0010` | R/W | 32 | Input Buffer write address pointer (0 to 1,023). |
| `REG_IBUF_DATA` | `0x1000_0014` | WO | 32 | Input Buffer write data register (lower 8 bits written as signed INT8). |
| `REG_WBUF_ADDR` | `0x1000_0020` | R/W | 32 | Weight Buffer write address pointer (0 to 8). |
| `REG_WBUF_DATA` | `0x1000_0024` | WO | 32 | Weight Buffer write data register (lower 8 bits written as signed INT8). |
| `REG_OBUF_ADDR` | `0x1000_0030` | R/W | 32 | Output Buffer read address pointer (0 to 899). |
| `REG_OBUF_DATA` | `0x1000_0034` | RO | 32 | Output Buffer read data register (full 32-bit signed INT32 result). |
| `REG_DEBUG` | `0x2000_0000` | R/W | 32 | Debug output register (monitored by testbench for firmware status). |

---

## 5. Repository Structure

```
riscv-int8-conv-soc/
├── .gitignore                      # Git exclusion rules for temporary build/log files
├── README.md                       # Comprehensive project documentation
├── SoC_RISCV.xpr                   # AMD Vivado 2025.1 project file
├── firmware.hex                    # Root firmware hex (304 bytes, 76 instructions)
├── rtl/                            # 14 RTL SystemVerilog / Verilog source files
│   ├── accelerator_mmio.sv
│   ├── conv2d_raster_scanner.sv
│   ├── conv_accelerator_top.sv
│   ├── conv_window_reader.sv
│   ├── dot9_int8.sv
│   ├── fpga_top.sv
│   ├── int8_multiplier.sv
│   ├── mac_int8.sv
│   ├── output_buffer.sv
│   ├── picorv32.v
│   ├── ram_sync_read.sv
│   ├── soc_ram.sv
│   ├── soc_top.sv
│   └── uart_tx.sv
├── tb/                             # 9 self-checking SystemVerilog testbenches
│   ├── tb_accelerator_mmio.sv
│   ├── tb_conv2d_raster_scanner.sv
│   ├── tb_conv_accelerator_top.sv
│   ├── tb_conv_window_reader.sv
│   ├── tb_dot9_int8.sv
│   ├── tb_int8_multiplier.sv
│   ├── tb_mac_int8.sv
│   ├── tb_output_buffer.sv
│   └── tb_soc_top.sv
├── constraints/                    # Timing and board constraint files
│   ├── stage4_timing.xdc
│   ├── stage5_timing.xdc
│   ├── stage6_timing.xdc
│   └── stage7_board.xdc            # Complete Basys 3 board constraints (pinouts & 100MHz clock)
├── firmware/                       # Bare-metal firmware sources & assembler
│   ├── firmware.hex                # Machine code hex image
│   ├── hw_demo.c                   # C reference algorithm implementation
│   ├── rv32i_assembler.py          # Python-based RV32I cross-assembler
│   └── test_accelerator.c          # C bare-metal driver testbench
├── scripts/                        # Vivado automation & verification scripts
│   ├── check_hardware.tcl          # Vivado Hardware Manager connection script
│   ├── create_project.tcl          # Script to recreate Vivado project from scratch
│   ├── run_all_regression.py       # Python automated runner for 9/9 regression tests
│   ├── run_tests.bat               # Windows batch regression test runner
│   ├── run_tests.ps1               # PowerShell regression test runner
│   ├── run_vivado_stage5.tcl       # Automated synthesis & impl for Stage 5
│   ├── run_vivado_stage6.tcl       # Automated synthesis & impl for Stage 6
│   └── run_vivado_stage7.tcl       # Full synthesis, impl, timing & bitstream for Stage 7
├── docs/                           # Detailed technical specifications and stage reviews
│   ├── stage1_spec.md
│   ├── stage2_spec.md
│   ├── stage3_spec.md
│   ├── stage4_spec.md & stage4_final_review.md
│   ├── stage5_spec.md & stage5_final_review.md
│   ├── stage6_spec.md & stage6_final_review.md
│   └── stage7_spec.md & stage7_final_review.md
└── build/                          # Implementation & timing reports
    ├── stage4_timing_summary.rpt
    ├── stage4_utilization.rpt
    └── reports/
        ├── stage5_utilization.rpt & stage5_timing_summary.rpt
        ├── stage6_utilization.rpt & stage6_timing_summary.rpt
        ├── stage7_utilization.rpt & stage7_utilization_hierarchical.rpt
        ├── stage7_timing_summary.rpt & stage7_drc_report.rpt
        └── stage7_io_report.rpt
```

---

## 6. Verification & Testbench Suite

The project enforces strict simulation verification with **9 self-checking testbenches** comparing RTL results against software Golden Models (Python and C).

### Automated Regression Execution

Run the complete regression suite using either Python, PowerShell, or Batch script:

```powershell
# Option 1: Python Regression Runner (cross-platform, formatted summary)
python scripts/run_all_regression.py

# Option 2: PowerShell Runner
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1

# Option 3: Command Prompt Batch Runner
.\scripts\run_tests.bat
```

### Verification Results Summary (Vivado Simulator v2025.1)

| # | Testbench File | Target Module | Verified Vectors / Coverage | Verification Result |
|---|---|---|---|:---:|
| 1 | `tb_int8_multiplier.sv` | `int8_multiplier` | Exhaustive $256 \times 256 = \mathbf{65,536}$ combinations | **PASS (65,536/65,536)** |
| 2 | `tb_mac_int8.sv` | `mac_int8` | 5,826 cycle checks, corner cases $[-128, +127]$ | **PASS (5,826/5,826)** |
| 3 | `tb_dot9_int8.sv` | `dot9_int8` | 137 tasks, 3,727 checks, backpressure & stalls | **PASS (137/137)** |
| 4 | `tb_conv_window_reader.sv` | `conv_window_reader`| 20 windows, 180 operand pairs, 1-cycle latency | **PASS (20/20)** |
| 5 | `tb_conv2d_raster_scanner.sv` | `conv2d_raster_scanner` | 9 full test sequences, boundary handling (0..29) | **PASS (9/9)** |
| 6 | `tb_output_buffer.sv` | `output_buffer` | 14 testcases, dual-port read/write integrity | **PASS (14/14)** |
| 7 | `tb_conv_accelerator_top.sv` | `conv_accelerator_top` | Full $32 \times 32$ convolution, $\mathbf{900 / 900}$ outputs vs Golden Model | **PASS (900/900)** |
| 8 | `tb_accelerator_mmio.sv` | `accelerator_mmio` | 7 testcases, MMIO register access & W1C protocol | **PASS (7/7)** |
| 9 | `tb_soc_top.sv` | `soc_top` | 7 integration stages: CPU boot, MMIO write, Accel start, Polling, Golden Check | **PASS (7/7)** |

---

## 7. FPGA Implementation & Resource Utilization

The complete SoC system was synthesized and implemented targeting the **Xilinx Artix-7 `xc7a35tcpg236-1`** FPGA on the Digilent Basys 3 board using AMD Vivado 2025.1:

### Resource Utilization Breakdown (Post-Implementation)

| Resource Primitives | System Total Used | Available on xc7a35t | Utilization (%) | Key Module Consumer |
|---|:---:|:---:|:---:|---|
| **Slice LUTs** | **1,297** | 20,800 | **6.24%** | PicoRV32 (1,038), MMIO (69), Scanner (189) |
| -- *LUT as Logic* | 1,281 | 20,800 | 6.16% | Logic gates, adders, decoders |
| -- *LUT as Memory* | 16 | 9,600 | 0.17% | Distributed RAM (Weight Buffer `RAM32M`) |
| **Slice Registers (FF)** | **1,114** | 41,600 | **2.68%** | PicoRV32 (565), Output Buffer (258) |
| **Block RAM (RAMB36E1)** | **5.5** (4x 36K + 3x 18K) | 50 | **11.00%** | SoC RAM (4x 36K = 16 KB), In/Out Buffers |
| **DSP48E1 Blocks** | **0** | 90 | **0.00%** | All 8-bit multipliers mapped to LUT logic |
| **Bonded IOBs** | **4** | 106 | **3.77%** | `sys_clk` (W5), `btn_reset` (U18), `uart_tx` (A18), `led_done` (U16) |

---

## 8. Static Timing Analysis (STA) & Design Rule Checks (DRC)

### Static Timing Summary (100.00 MHz Target Clock)
Extracted from Vivado implementation report [`build/reports/stage7_timing_summary.rpt`](build/reports/stage7_timing_summary.rpt):

- **Target Frequency:** $100.00\text{ MHz}$ ($T_{\text{period}} = 10.000\text{ ns}$)
- **Setup Timing Slack (WNS):** **$+0.255\text{ ns}$** ($> 0\text{ ns}$, **MET**)
- **Total Negative Slack (TNS):** $0.000\text{ ns}$ (0 failing endpoints out of 3,026)
- **Hold Timing Slack (WHS):** **$+0.035\text{ ns}$** ($> 0\text{ ns}$, **MET**)
- **Total Hold Slack (THS):** $0.000\text{ ns}$ (0 failing endpoints)
- **Worst Pulse Width Slack (WPWS):** **$+3.750\text{ ns}$** (0 failing endpoints out of 991)
- **Timing Constraint Verdict:** **All user-specified timing constraints are met.**

### Design Rule Check (DRC) Status
Extracted from [`build/reports/stage7_drc_report.rpt`](build/reports/stage7_drc_report.rpt):
- **Errors:** 0
- **Critical Warnings:** 0
- **Information Warnings:** 12 warnings for rule `REQP-1839` (*RAMB36 async control check*).
  - *Technical Cause:* The reset signal driving the `ENARDEN`, `ENBWREN`, and `RSTRAMB` control pins of the 4 `RAMB36E1` primitives in `soc_ram` originates from `rst_sync_1_reg`, which possesses an asynchronous clear assertion input.
  - *Impact:* These are informational advisory checks that do not impede bitstream generation (`fpga_top.bit` successfully generated).

---

## 9. How to Build & Reproduce

### Prerequisites
- AMD Vivado Design Suite 2025.1 (or compatible 2022.x/2023.x/2024.x).
- Python 3.8+ (for cross-assembler and regression verification script).

### Recreate Vivado Project & Run Implementation
You can execute automated TCL scripts directly inside Vivado Tcl Shell:

```tcl
# Open Vivado in batch or GUI mode:
vivado -mode tcl

# 1. Recreate the complete project from sources:
source scripts/create_project.tcl

# 2. Run full implementation and bitstream generation:
source scripts/run_vivado_stage7.tcl
```

The bitstream file will be generated at `build/stage7/fpga_top.bit`.

---

## 10. Known Limitations & Future Work

1. **Physical Board Bring-Up (Hardware Test Pending):**
   - The design has achieved the **PASS TO BITSTREAM** milestone (synthesis, place-and-route, 100 MHz timing closure, and DRC passed). Physical hardware validation on the Digilent Basys 3 board is pending in the next project phase.
2. **Sequential MAC Datapath:**
   - The convolution core computes 9 elements sequentially in 11 cycles per window using 1 MAC. Future work can implement 9 parallel MAC units to achieve 1-cycle-per-window throughput.
3. **MMIO Bus Polling Overhead:**
   - Transferring 1,024 input bytes and reading 900 output words is handled via CPU memory instructions (`SW`/`LW`). Integrating a Direct Memory Access (DMA) engine with AXI4/TileLink would significantly alleviate CPU bus contention.
4. **Pushbutton Debouncing:**
   - The 2-stage FF AASD synchronizer prevents reset metastability upon deassertion but does not include a counter-based debounce filter for mechanical button vibrations.

---

## 11. Authors & Academic Context

- **Authors:**
  - **Phạm Thế Cường** (Pham The Cuong) — Student ID: `23161239` (GitHub: [`ptcuong211`](https://github.com/ptcuong211))
  - **Hoàng Gia Bảo** (Hoang Gia Bao) — Student ID: `23161226`
- **Institution:** Department of Electronics & Telecommunications Engineering
- **Academic Milestone:** Capstone Project 2 (Đồ án 2) — 2026
