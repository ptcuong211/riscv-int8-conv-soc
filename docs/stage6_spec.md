# TÀI LIỆU ĐẶC TẢ KỸ THUẬT VÀ THIẾT KẾ STAGE 6 (STAGE 6 SPECIFICATION)
## RISC-V SoC Integration: PicoRV32 CPU + 16KB RAM + MMIO Interconnect + INT8 Conv Accelerator

**Dự án:** RISC-V SoC tích hợp bộ tăng tốc Convolution INT8 trên FPGA  
**Đối tượng:** Sinh viên ngành Kỹ thuật Máy tính / Điện tử - Thiết kế Vi mạch RTL  
**Workspace:** `D:\DA2\SoC RISCV`  
**Target FPGA:** AMD/Xilinx Artix-7 `xc7a35tcpg236-1`  
**Tần số xung nhịp mục tiêu:** 100 MHz (Chu kỳ: 10.000 ns)  
**Ngày hoàn thành:** 31/10/2026  

---

## 1. Mục Tiêu Giai Đoạn 6 (Stage 6 Objectives)

Giai đoạn 6 đánh dấu bước chuyển mình quan trọng nhất của toàn bộ đề tài: **Chuyển từ một bộ tăng tốc phần cứng độc lập sang một Hệ thống trên vi mạch (System-on-Chip - SoC) hoàn chỉnh**.

Mục tiêu kỹ thuật cốt lõi:
1. **Tích hợp bộ vi xử lý RISC-V PicoRV32**: Cấu hình tập lệnh chuẩn RV32I, 32 thanh ghi đa dụng, hỗ trợ giao diện bộ nhớ Native Memory Bus.
2. **Thiết kế bộ nhớ RAM SoC (Unified Memory)**: Dung lượng 16 KiB ($4096 \times 32$-bit), suy luận Block RAM (`RAMB36E1`), hỗ trợ ghi từng byte (byte strobe) phục vụ cả lưu trữ mã lệnh (instructions) lẫn dữ liệu/ngăn xếp (data/stack).
3. **Thiết kế bộ giải mã địa chỉ & bộ điều khiển MMIO (`accelerator_mmio`)**: Cung cấp giao diện thanh ghi điều khiển, trạng thái và dữ liệu ánh xạ bộ nhớ để CPU có thể truy cập toàn bộ Accelerator thông qua các lệnh đọc/ghi bộ nhớ tiêu chuẩn (`lw` / `sw`).
4. **Kết nối CPU ↔ Accelerator**: Đảm bảo bắt tay bus an toàn, xử lý triệt để độ trễ đọc BRAM (1-cycle latency), tạo xung `start` 1 chu kỳ chuẩn xác và cơ chế cờ `sticky_done` kèm xóa cờ W1C.
5. **Hiện thực Firmware Bare-metal**: Viết mã nguồn C (`firmware/test_accelerator.c`) và công cụ biên dịch tạo tệp khởi tạo mã máy RV32I (`firmware.hex`).
6. **Kiểm chứng toàn diện End-to-End**: Testbench `tb_soc_top` mô phỏng thực tế quá trình CPU boot từ ROM/RAM, nạp dữ liệu, khởi chạy accelerator, chờ cờ xong và kiểm tra 900 kết quả tích chập 32-bit.
7. **Tổng hợp & Định tuyến FPGA thực tế**: Đạt tần số 100 MHz trên chip Artix-7 `xc7a35t` với WNS dương.

---

## 2. Kiến Trúc Tổng Thể RISC-V SoC (`soc_top`)

```text
                                         soc_top
+-----------------------------------------------------------------------------------------------+
|                                                                                               |
|   +-----------------------+                                                                   |
|   |   PicoRV32 CPU Core   |                                                                   |
|   |  - RV32I (32 Regs)    |                                                                   |
|   |  - Native Memory Bus  |                                                                   |
|   +-----------+-----------+                                                                   |
|               | cpu_mem_*                                                                     |
|               v                                                                               |
|   +---------------------------------------------------------------------------------------+   |
|   |                     Address Decoder & Interconnect Bus Logic                          |   |
|   +-----------+-----------------------------------+-----------------------------------+---+   |
|               | 0x0000_0000                       | 0x1000_0000                       |       |
|               v (16 KiB)                          v (MMIO Range)                      | 0x2000_0000
|   +-----------------------+           +-----------------------+                       v       |
|   |        soc_ram        |           |   accelerator_mmio    |           +---------------+   |
|   |  4096 x 32-bit BRAM   |           |  - CSR Control/Status |           |  Debug Reg    |   |
|   |  (Byte-enabled write) |           |  - IBUF/WBUF Ports    |           | (0xCAFE0001)  |   |
|   +-----------------------+           |  - OBUF Read Port     |           +---------------+   |
|                                       +-----------+-----------+                               |
|                                                   |                                           |
|                                                   v                                           |
|                                       +-----------------------+                               |
|                                       | conv_accelerator_top  |                               |
|                                       |  - conv2d_scanner     |                               |
|                                       |  - conv_window_reader |                               |
|                                       |  - dot9_int8 datapath |                               |
|                                       |  - output_buffer BRAM |                               |
|                                       +-----------------------+                               |
|                                                                                               |
+-----------------------------------------------------------------------------------------------+
```

---

## 3. Không Gian Địa Chỉ Bộ Nhớ (SoC Memory Map)

Không gian địa chỉ 32-bit được phân bổ rõ ràng theo 4-bit cao `addr[31:28]`:

| Dải địa chỉ | Kích thước | Tên ngoại vi / Vùng nhớ | Chức năng |
|---|:---:|---|---|
| `0x0000_0000 - 0x0000_3FFF` | 16 KiB | **SoC Unified RAM** | Chứa mã thực thi (Text), Dữ liệu (Data/BSS) và Ngăn xếp (Stack) |
| `0x1000_0000 - 0x1000_001F` | 32 Bytes | **Accelerator MMIO** | Các thanh ghi điều khiển, trạng thái và cổng nạp/đọc bộ đệm |
| `0x2000_0000 - 0x2000_0003` | 4 Bytes | **Debug Register** | Ghi mã trạng thái kiểm tra testbench (`0xCAFE0001` = PASS) |
| Khác (`> 0x2FFF_FFFF`) | — | **Invalid Address** | Tự động trả lời `ready = 1` và `0xDEADDEAD` để chống treo CPU bus |

---

## 4. Chi Tiết Các Thanh Ghi MMIO (`accelerator_mmio`)

Địa chỉ cơ sở (Base Address): **`0x1000_0000`**

| Offset | Tên thanh ghi | Truy cập | Ý nghĩa các bit |
|---|---|:---:|---|
| `0x00` | `ACCEL_CTRL` | W | **Bit 0 (START):** Ghi `1` tạo xung kích hoạt accelerator đúng 1 chu kỳ clock. Tự động xóa về 0. |
| `0x04` | `ACCEL_STATUS` | R / W1C | **Bit 0 (BUSY):** Trạng thái bận của accelerator (1 = đang tính, 0 = rỗi).<br>**Bit 1 (DONE):** Cờ báo hoàn tất 900 kết quả (Sticky bit). Ghi `1` vào bit này để xóa cờ (Write-1-to-Clear). |
| `0x08` | `REG_IBUF_ADDR` | R / W | Địa chỉ nạp Input Buffer ($0 \to 1023$, 10-bit). |
| `0x0C` | `REG_IBUF_DATA` | W | Ghi byte pixel (signed INT8) vào vị trí `REG_IBUF_ADDR`. Tự sinh xung `ibuf_wr_en` 1 chu kỳ. |
| `0x10` | `REG_WBUF_ADDR` | R / W | Địa chỉ nạp Weight Buffer ($0 \to 8$, 4-bit). |
| `0x14` | `REG_WBUF_DATA` | W | Ghi byte trọng số (signed INT8) vào `REG_WBUF_ADDR`. Tự sinh xung `wbuf_wr_en` 1 chu kỳ. |
| `0x18` | `REG_OBUF_ADDR` | R / W | Địa chỉ trích xuất Output Buffer ($0 \to 899$, 10-bit). |
| `0x1C` | `REG_OBUF_DATA` | R | Đọc giá trị kết quả tích chập signed INT32 từ Output Buffer tại địa chỉ `REG_OBUF_ADDR`. |

---

## 5. Xử Lý Bắt Tay Bus & Độ Trễ Đọc BRAM (Bus Handshake & Latency)

### Giao thức Native Memory Bus của PicoRV32:
- CPU phát tín hiệu yêu cầu: `mem_valid = 1`, `mem_addr`, `mem_wdata`, `mem_wstrb`.
- CPU giữ nguyên các tín hiệu này và chờ cho tới khi slave trả lời `mem_ready = 1` tại cạnh lên của xung nhịp clock.
- Tại chu kỳ mà `mem_valid && mem_ready == 1`, giao dịch hoàn tất.

### Xử lý độ trễ đọc BRAM trong SoC:
- Cả `soc_ram` và `output_buffer` đều là Block RAM phần cứng có **độ trễ đọc 1 chu kỳ (1-Cycle Latency)**.
- Khối `soc_ram` và `accelerator_mmio` triển khai cơ chế **1-wait-state registered ready**:
  - Chu kỳ $T$: CPU phát `mem_valid = 1`. Slave ghi nhận địa chỉ, BRAM thực hiện giải mã và trích xuất dữ liệu. Slave đặt cờ `ready_q <= 1'b1;`.
  - Chu kỳ $T+1$: Dữ liệu từ BRAM xuất hiện ổn định ở bus đọc `mem_rdata`. Tín hiệu `mem_ready = ready_q = 1`. CPU tiếp nhận dữ liệu thành công.
  - Thiết kế này triệt tiêu hoàn toàn đường trễ tổ hợp (combinational loop), giúp hệ thống đạt tần số 100 MHz dễ dàng.

---

## 6. Luồng Thực Thi Firmware End-to-End

Chương trình điều khiển chạy trên CPU PicoRV32 tuân theo quy trình tuần tự:
```text
1. Khởi tạo con trỏ ngăn xếp (sp = 0x00003FFC)
2. Nạp ma trận ảnh 32x32:
   Lặp i từ 0 đến 1023:
     Ghi i vào REG_IBUF_ADDR
     Ghi 1 vào REG_IBUF_DATA
3. Nạp ma trận kernel 3x3:
   Lặp i từ 0 đến 8:
     Ghi i vào REG_WBUF_ADDR
     Ghi 1 vào REG_WBUF_DATA
4. Khởi động bộ tăng tốc:
   Ghi 1 vào REG_ACCEL_CTRL (Kích hoạt START)
5. Chờ hoàn tất (Polling):
   Đọc REG_ACCEL_STATUS
   Kiểm tra (STATUS & 0x02): Lặp lại nếu bằng 0
   Ghi 2 vào REG_ACCEL_STATUS để xóa cờ DONE (W1C)
6. Thu thập và kiểm tra kết quả:
   Lặp i từ 0 đến 899:
     Ghi i vào REG_OBUF_ADDR
     Đọc val từ REG_OBUF_DATA
     Nếu val != 9: Ghi mã lỗi (0xDEAD0001) vào DEBUG_REG và dừng
7. Báo kết quả lượt 1 thành công:
   Ghi 0xCAFE0001 vào DEBUG_REG (0x20000000)
8. Chạy lại lần 2 (Re-run Test):
   Lặp lại toàn bộ các bước từ 2 đến 6
   Ghi 0xCAFE0002 vào DEBUG_REG (Xác nhận SoC hoàn tất 100%)
```

---

## 7. Báo Cáo Triển Khai Phần Cứng FPGA (Vivado Implementation Report)

Tổng hợp trên chip thực tế **Xilinx Artix-7 `xc7a35tcpg236-1`** tại tần số **100 MHz**:

### 7.1. Bảng Tiêu Thụ Tài Nguyên Chi Tiết (Device Utilization)

| Khối chức năng / Module | Logic LUTs | LUTRAMs | Flip-Flops (FF) | RAMB36E1 | RAMB18E1 | DSPs |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Toàn bộ SoC (`soc_top`)** | **1,178** | **50** | **834** | **5** | **1** | **0** |
| - `u_cpu` (PicoRV32 Core) | 980 | 44 | 488 | 0 | 0 | 0 |
| - `u_ram` (16 KiB Unified RAM)| 0 | 0 | 0 | 4 | 0 | 0 |
| - `u_accelerator` (Conv Top) | 183 | 6 | 202 | 1 | 1 | 0 |
| - `u_accel_mmio` (MMIO Logic) | 13 | 0 | 77 | 0 | 0 | 0 |
| - Logic giải mã bus & Debug | 2 | 0 | 67 | 0 | 0 | 0 |
| **Tổng số trên chip Artix-7 35T** | **20,800** | **9,600** | **41,600** | **50** | **100** | **90** |
| **Tỷ lệ chiếm dụng (%)** | **5.66%** | **0.52%** | **2.00%** | **10.00%** | **1.00%** | **0.00%** |

### 7.2. Phân Tích Định Thời Tại 100 MHz (Clock Period = 10.000 ns)

```text
------------------------------------------------------------------------------------------------
| Design Timing Summary
------------------------------------------------------------------------------------------------
    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)
    -------      -------  ---------------------  -------------------      -------      -------
      0.011        0.000                      0                 2447        0.060        0.000

All user specified timing constraints are met.
```

- **Worst Negative Slack (WNS):** `+0.011 ns` (Thặng dư thời gian dương, thỏa mãn chu kỳ 10.000 ns ở 100 MHz).
- **Total Negative Slack (TNS):** `0.000 ns` (0/2,447 endpoints vi phạm).
- **Worst Hold Slack (WHS):** `+0.060 ns` (Không vi phạm Hold time).
- **Zero Errors, Zero Critical Warnings**.

---

## 8. Hạn Chế Hiện Tại & Định Hướng Phát Triển Tiếp Theo

1. **Giao tiếp ngoại vi bên ngoài**: Chưa tích hợp UART Transmitter để xuất chuỗi ký tự kết quả trực tiếp lên màn hình máy tính thông qua cáp micro-USB của kit phát triển FPGA.
2. **Cơ chế ngắt (Interrupt)**: Hiện tại CPU sử dụng phương pháp Polling cờ `DONE`. Trong các ứng dụng phức tạp hơn, ngắt phần cứng (`irq`) sẽ giúp CPU giải phóng tài nguyên trong khi accelerator đang xử lý.
3. **Phát triển ứng dụng CNN nhiều lớp**: Giai đoạn tiếp theo có thể hỗ trợ nhiều kênh (channels), padding, hàm kích hoạt ReLU và Max-Pooling để hoàn thiện mạng CNN phân loại chữ số viết tay MNIST.

