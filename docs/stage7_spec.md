# TÀI LIỆU ĐẶC TẢ KỸ THUẬT STAGE 7: FPGA BOARD BRING-UP & HARDWARE DEMO

---

## 1. TỔNG QUAN

Stage 7 hiện thực hóa hệ thống **RISC-V SoC tích hợp bộ tăng tốc Convolution INT8 2D** từ mức mô phỏng RTL và kiểm tra synthesis sang chạy thực tế trên phần cứng FPGA:
- **Board mục tiêu:** Digilent Basys 3 Artix-7 FPGA Board
- **FPGA Part:** AMD/Xilinx Artix-7 `xc7a35tcpg236-1`
- **Tần số hoạt động:** 100.00 MHz (chu kỳ 10.00 ns) từ bộ dao động thạch anh trên board
- **Top-level module:** `rtl/fpga_top.sv`
- **Giao tiếp quan sát trực quan:** 16 đèn LED người dùng (Visual Status Indicators)
- **Giao tiếp xuất log gỡ lỗi:** UART Serial Transmitter (115,200 Baud, 8-N-1) qua cầu nối USB-UART FT2232
- **Cơ chế nạp chương trình:** Khởi tạo trực tiếp nội dung Unified 16 KiB Block RAM (`firmware.hex`) vào file Bitstream (`fpga_top.bit`).

---

## 2. KIẾN TRÚC TỔNG THỂ PHẦN CỨNG (fpga_top)

```text
+---------------------------------------------------------------------------------------------------+
| Digilent Basys 3 (xc7a35tcpg236-1)                                                                |
|                                                                                                   |
|  Pin W5 (100MHz Osc) ---> [ BUFG ] ---> sys_clk (100MHz)                                          |
|                                                                                                   |
|  Pin U18 (btnC Reset) ---> [ 2-Stage AASD Sync ] ---> sys_rst (Active-High)                       |
|                                                                                                   |
|  +---------------------------------------------------------------------------------------------+  |
|  | soc_top (RISC-V SoC Core)                                                                   |  |
|  |                                                                                             |  |
|  |   +-------------------+    Native Bus    +-----------------------------------------------+  |  |
|  |   | PicoRV32 Core     | <--------------> | Address Decoder (soc_top)                     |  |  |
|  |   | (RV32I, Baremetal)|                  |  - 0x0000_0000 : Unified RAM 16 KiB (soc_ram) |  |  |
|  |   +-------------------+                  |  - 0x1000_0000 : Accelerator MMIO             |  |  |
|  |             |                            |  - 0x2000_0000 : Debug Register               |  |  |
|  |             v trap                       +-----------------------------------------------+  |  |
|  |                                                        |                                    |  |
|  |                                                        v                                    |  |
|  |                                          +-----------------------------------------------+  |  |
|  |                                          | conv_accelerator_top (INT8 2D Hardware Accel) |  |  |
|  |                                          |  - Input Buffer:  1024 x 8-bit RAM            |  |  |
|  |                                          |  - Weight Buffer: 9 x 8-bit RAM               |  |  |
|  |                                          |  - Dot9 INT8 Engine (9 MACs Pipeline)         |  |  |
|  |                                          |  - Scanner FSM (30x30 = 900 windows)          |  |  |
|  |                                          |  - Output Buffer: 900 x 32-bit Dual-Port BRAM |  |  |
|  |                                          +-----------------------------------------------+  |  |
|  +---------------------------------------------------------------------------------------------+  |
|       |                 |                   |                   |                                 |
|       v trap            v debug_out         v accel_busy        v accel_done                      |
|  +---------------------------------------------------------------------------------------------+  |
|  | Mach giam sat & dieu khien Visual Debug (fpga_top)                                          |  |
|  |                                                                                             |  |
|  |  - Heartbeat Counter (26-bit, ~1.5 Hz toggle) -> LED15 (Alive Blinker)                      |  |
|  |  - Status Decoder -> LED14 (Busy), LED13 (Latched Done), LED12 (Trap)                       |  |
|  |  - Pass Indicators -> LED1 (Run 1 Pass), LED2 (Run 2 Pass), LED0 (All Tests Passed)        |  |
|  |  - Debug Out Lower Nibbles -> LED7..LED4                                                    |  |
|  |  - UART String Reporter FSM -> uart_tx (115200 baud) -> Pin A18 (USB-UART TX)                |  |
|  +---------------------------------------------------------------------------------------------+  |
+---------------------------------------------------------------------------------------------------+
```

---

## 3. SƠ ĐỒ CHÂN VẬT LÝ & ĐẶC TẢ CONSTRAINTS (stage7_board.xdc)

Toàn bộ các chân I/O tuân thủ chính xác theo tài liệu phần cứng chuẩn của Digilent Basys 3:

| Tên cổng RTL (`fpga_top`) | Chân FPGA vật lý | Chuẩn điện áp | Hướng I/O | Chức năng phần cứng trên Basys 3 |
| :--- | :--- | :--- | :--- | :--- |
| `clk_100mhz` | `W5` | `LVCMOS33` | Input | Bộ dao động thạch anh 100 MHz trên board |
| `btn_reset` | `U18` | `LVCMOS33` | Input | Nút bấm tròn trung tâm (`btnC`), nhấn mức cao = Reset |
| `uart_tx_out` | `A18` | `LVCMOS33` | Output | Chân nhận UART RX của chip cầu nối FT2232 USB-to-UART |
| `led[0]` | `U16` | `LVCMOS33` | Output | Đèn LED0 (Sáng khi toàn bộ bài test phần cứng PASS) |
| `led[1]` | `E19` | `LVCMOS33` | Output | Đèn LED1 (Sáng khi Run 1: All-Ones 30x30 PASS) |
| `led[2]` | `U19` | `LVCMOS33` | Output | Đèn LED2 (Sáng khi Run 2: Dataset 2 Re-run PASS) |
| `led[3]` | `V19` | `LVCMOS33` | Output | Đèn LED3 (Dự phòng) |
| `led[4]` | `W18` | `LVCMOS33` | Output | Đèn LED4 (`debug_out[0]`) |
| `led[5]` | `U15` | `LVCMOS33` | Output | Đèn LED5 (`debug_out[1]`) |
| `led[6]` | `U14` | `LVCMOS33` | Output | Đèn LED6 (`debug_out[2]`) |
| `led[7]` | `V14` | `LVCMOS33` | Output | Đèn LED7 (`debug_out[3]`) |
| `led[8]` | `V13` | `LVCMOS33` | Output | Đèn LED8 (Trạng thái trung gian) |
| `led[9]` | `V3`  | `LVCMOS33` | Output | Đèn LED9 (Trạng thái trung gian) |
| `led[10]` | `W3` | `LVCMOS33` | Output | Đèn LED10 (Trạng thái trung gian) |
| `led[11]` | `U3` | `LVCMOS33` | Output | Đèn LED11 (Trạng thái trung gian) |
| `led[12]` | `P3` | `LVCMOS33` | Output | Đèn LED12 (Báo lỗi CPU Trap: đỏ/sáng nếu vi xử lý dừng) |
| `led[13]` | `N3` | `LVCMOS33` | Output | Đèn LED13 (Báo Accelerator Done: chốt sáng sau khi hoàn tất) |
| `led[14]` | `P1` | `LVCMOS33` | Output | Đèn LED14 (Báo Accelerator Busy: sáng khi accelerator đang tính) |
| `led[15]` | `L1` | `LVCMOS33` | Output | Đèn LED15 (Heartbeat: chớp tắt liên tục báo clock và CPU sống) |

---

## 4. GIAO TIẾP VÀ TRUYỀN THÔNG UART DEBUG (rtl/uart_tx.sv)

Để người dùng có thể mở terminal máy tính (PuTTY, Tera Term, Serial Port Monitor) và đọc kết quả chi tiết:
- **Tốc độ baud:** 115,200 bps
- **Khung truyền:** 8 Data bits, No parity, 1 Stop bit (8-N-1)
- **Hệ số chia xung:** `CLKS_PER_BIT = 100,000,000 / 115,200 = 868` chu kỳ xung 100 MHz
- **Thông điệp truyền tự động sau khi hoàn tất:**
  - Khi hoàn tất Run 1: Gửi chuỗi ASCII `"[HW DEMO] RUN 1 PASS!\r\n"`
  - Khi hoàn tất Run 2: Gửi chuỗi ASCII `"[HW DEMO] RUN 2 PASS! ALL TESTS COMPLETED SUCCESSFULLY!\r\n"`
  - Khi CPU gặp lỗi Trap: Gửi chuỗi ASCII `"[HW DEMO] CPU TRAP DETECTED!\r\n"`

---

## 5. BẢN ĐỒ BỘ NHỚ VÀ ĐỊA CHỈ MMIO (SoC Memory Map)

| Khoảng địa chỉ (Byte Hex) | Kích thước | Ngoại vi mục tiêu | Giao thức truy cập |
| :--- | :--- | :--- | :--- |
| `0x0000_0000 - 0x0000_3FFF` | 16 KiB | Unified Instruction & Data RAM | 32-bit RW (1-wait-state BRAM) |
| `0x1000_0000` | 4 Byte | Control Register (`START` xung bit 0) | 32-bit WO |
| `0x1000_0004` | 4 Byte | Status Register (bit 0 = `BUSY`, bit 1 = `DONE`) | 32-bit RO |
| `0x1000_0800 - 0x1000_0BFF` | 1024 Byte | Input Buffer (`32x32` signed INT8 pixels) | 32-bit WO |
| `0x1000_0C00 - 0x1000_0C23` | 36 Byte | Weight Buffer (`3x3` signed INT8 weights) | 32-bit WO |
| `0x1000_1000 - 0x1000_1E0F` | 3600 Byte | Output Buffer (`30x30 = 900` signed INT32) | 32-bit RO (1-wait-state BRAM) |
| `0x2000_0000` | 4 Byte | System Debug Register (`0xCAFE0001` / `0xCAFE0002`) | 32-bit RW |

---

## 6. THUẬT TOÁN VÀ KỊCH BẢN KIỂM THỬ TRÊN PHẦN CỨNG (firmware/hw_demo.c)

Chương trình firmware chạy độc lập trên PicoRV32 thực hiện 2 giai đoạn kiểm thử liên tiếp:

### Giai đoạn 1: All Ones Convolution
1. Ghi 1024 pixel giá trị `+1` vào Input Buffer.
2. Ghi 9 trọng số giá trị `+1` vào Weight Buffer.
3. Kích phát bit `START` (ghi `1` vào `0x10000000`).
4. Polling thanh ghi `STATUS` (`0x10000004`) cho đến khi `BUSY == 0` và `DONE == 1`.
5. Đọc tuần tự toàn bộ 900 kết quả INT32 từ Output Buffer.
6. So sánh từng kết quả với giá trị chuẩn: `1*1*9 = 9`.
7. Nếu 900/900 kết quả chính xác: Ghi `0xCAFE0001` vào Debug Register (bật LED1).

### Giai đoạn 2: Dataset 2 Re-run Test
1. Ghi đè 1024 pixel giá trị `+2` vào Input Buffer.
2. Giữ nguyên 9 trọng số giá trị `+1`.
3. Kích phát `START` lần thứ 2.
4. Polling chờ `DONE == 1`.
5. Đọc tuần tự 900 kết quả từ Output Buffer.
6. So sánh từng kết quả với giá trị chuẩn: `2*1*9 = 18`.
7. Nếu 900/900 kết quả chính xác: Ghi `0xCAFE0002` vào Debug Register (bật LED2 và LED0).

