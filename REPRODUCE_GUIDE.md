# HƯỚNG DẪN TÁI TẠO VÀ KIỂM CHỨNG ĐỒ ÁN 2
## RISC-V SoC TÍCH HỢP BỘ TĂNG TỐC TÍCH CHẬP CNN INT8

### 1. Thông tin cấu hình
- Commit: c40f793 (Branch: fix/f03-verification)
- Công cụ: AMD/Xilinx Vivado 2025.1
- Bo mạch mục tiêu: Digilent Basys 3 (Artix-7 xc7a35tcpg236-1)
- Xung nhịp hệ thống: 100.00 MHz (chu kỳ 10.0 ns)

### 2. Chạy kiểm chứng hồi quy toàn bộ 9 Testbench (Vivado Simulator)
```powershell
cd scripts
python run_all_regression.py
```
Kết quả kỳ vọng: 9/9 PASS (100% vectors pass, 0 fail).

### 3. Chạy kiểm chứng chuyên biệt an toàn Reset BRAM (F-01)
```powershell
python scripts/run_reset_safety_test.py
```
Kết quả kỳ vọng: 10/10 Directed Reset Safety Tests PASS.

### 4. Chạy kiểm chứng giải mã truyền thông UART nối tiếp (F-02)
```powershell
python scripts/run_uart_verification.py
```
Kết quả kỳ vọng: 57/57 bytes ASCII thu nhận chính xác 100%, 0 framing error.

### 5. Tái tạo quy trình Implementation và Bitstream trên Vivado
```powershell
vivado -mode batch -source scripts/run_vivado_stage7.tcl
```
Kết quả kỳ vọng:
- WNS = +0.114 ns, WHS = +0.051 ns (Timing closed).
- DRC: 0 Errors, 0 Critical Warnings, 0 Warnings (REQP-1839 triệt tiêu).
- Xuất thành công file bitstream: build/stage7/fpga_top.bit.
