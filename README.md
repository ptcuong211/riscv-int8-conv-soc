# Hệ Thống SoC RISC-V Tích Hợp Bộ Tăng Tốc Tính Toán INT8 Trên FPGA

Dự án đồ án chuyên ngành thiết kế phần cứng vi mạch (RTL Design) hướng đến việc hiện thực một hệ thống SoC (System-on-Chip) hoàn chỉnh dựa trên kiến trúc tập lệnh RISC-V, tích hợp bộ tăng tốc phần cứng (Hardware Accelerator) chuyên dụng cho phép tính tích chập (2D Convolution) số nguyên signed INT8.

---

## 1. Phân định Thành phần Thiết kế và Phạm vi Đồ án

Nhằm đảm bảo tính minh bạch học thuật và chuẩn mực kỹ thuật trong đồ án vi mạch:

### 1.1 Khối phần cứng tự thiết kế (Custom RTL)
- **Đường xử lý dữ liệu (Datapath Accelerator)**:
  - Khối nhân số nguyên có dấu `int8_multiplier` (8-bit $\times$ 8-bit $\to$ 16-bit).
  - Khối nhân tích lũy `mac_int8` (Accumulator 32-bit, Sign Extension).
  - Khối trượt ma trận và bộ đệm dòng (Line Buffers / Window Buffers).
- **Khối điều khiển (Control Path)**:
  - Máy trạng thái hữu hạn (FSM) và bộ đếm đồng bộ điều khiển chu trình tính toán 9 cặp kernel $3 \times 3$.
  - Khối sinh tín hiệu báo bận (BUSY), hoàn thành (DONE) và điều khiển luồng (Valid/Ready).
- **Khối kết nối hệ thống (Interconnect & MMIO)**:
  - Bộ giải mã địa chỉ và thanh ghi cấu hình MMIO (Control/Status Registers).
  - Giao tiếp cầu nối giữa bus của CPU và Accelerator.
- **Phần mềm nhúng (Bare-metal Firmware)**:
  - Firmware C khởi tạo dữ liệu, kích hoạt tăng tốc, kiểm tra cờ ngắt/polling và giao tiếp UART.

### 1.2 Thành phần bên thứ ba / IP có sẵn (Third-party IPs)
- **Lõi vi xử lý (CPU Core)**: PicoRV32 (cấu hình RV32IM: hỗ trợ tập lệnh nguyên và nhân/chia phần cứng).
- **Bộ nhớ nội (On-chip Memory)**: Khối FPGA Block RAM (BRAM) cho Program/Data RAM.
- **Ngoại vi giao tiếp (Peripherals)**: Khối UART Controller tiêu chuẩn để xuất log và kết quả đo đạc.

### 1.3 Phân biệt phạm vi tính năng
> [!IMPORTANT]
> **Khác biệt quan trọng**: Hệ thống accelerator trong đồ án này tập trung hiện thực và tăng tốc **phép tính tích chập 2D (2D Convolution Layer)** với dữ liệu INT8, không phải toàn bộ một pipeline mạng nơ-ron sâu phức tạp (như ResNet/YOLO) bao gồm đầy đủ các lớp Pooling, Requantization phi tuyến, Softmax, v.v. Việc chứng minh tăng tốc phần cứng thành công dựa trên so sánh trực tiếp thời gian thực thi của phép tích chập trên phần cứng accelerator so với CPU tính toán bằng phần mềm thuần túy.

---

## 2. Lộ Trình Triển Khai 8 Tuần

| Giai đoạn | Nội dung công việc | Tiêu chí hoàn thành (Exit Criteria) | Trạng thái |
|:---:|---|---|:---:|
| **1** | **Bộ nhân signed INT8 và MAC INT32** | Testbench tự kiểm tra đạt PASS 100% | **HOÀN THÀNH** |
| **2** | **FSM và bộ đếm điều khiển MAC tính 9 cặp (`dot9_int8`)** | Kích hoạt START, handshake valid-ready, cờ DONE đúng chu kỳ | **HOÀN THÀNH** |
| **3** | **Bộ đệm RAM đồng bộ & Trích xuất cửa sổ 3x3 (`conv_window_reader`)** | Đọc đồng bộ 1-cycle latency, cấp 9 cặp chuẩn xác, khớp Golden Model | **HOÀN THÀNH** |
| **4** | Accelerator convolution cho toàn bức ảnh | Khớp từng pixel output 30x30 với mô hình Python | Kế tiếp |
| **5** | Tích hợp CPU PicoRV32, Bus, Bộ nhớ và UART | CPU chạy firmware C bare-metal in chuỗi Hello qua UART | Chờ |
| **6** | Giao tiếp MMIO và Driver điều khiển | CPU nạp ảnh, ra lệnh tính, đọc kết quả và so sánh tự động | Chờ |
| **7** | Triển khai FPGA, tối ưu Timing & Resource | Đạt tần số clock mục tiêu, tối ưu số lượng DSP/LUT | Chờ |
| **8** | Đo đạc Benchmark và Báo cáo tổng kết | Số liệu tăng tốc phần cứng thực tế và báo cáo đồ án | Chờ |

---

## 3. Cấu Trúc Workspace

```
SoC RISCV/
├── rtl/                        # Mã nguồn RTL SystemVerilog tự thiết kế
│   ├── int8_multiplier.sv      # Khối nhân signed INT8 tổ hợp (Giai đoạn 1)
│   ├── mac_int8.sv             # Khối nhân - tích lũy INT8/INT32 (Giai đoạn 1)
│   ├── dot9_int8.sv            # FSM & Handshake tính 9 cặp kernel (Giai đoạn 2)
│   ├── ram_sync_read.sv        # RAM đọc đồng bộ (suy diễn Block RAM) (Giai đoạn 3)
│   └── conv_window_reader.sv   # Bộ đệm RAM & Trích xuất cửa sổ 3x3 (Giai đoạn 3)
├── tb/                         # Testbench SystemVerilog tự kiểm tra
│   ├── tb_int8_multiplier.sv   # Kiểm tra toàn diện 65,536 tổ hợp
│   ├── tb_mac_int8.sv          # Kiểm tra chu kỳ, giá trị biên, hồi quy ngẫu nhiên
│   ├── tb_dot9_int8.sv         # Kiểm tra FSM, stall, backpressure, 120 tác vụ ngẫu nhiên
│   └── tb_conv_window_reader.sv # Kiểm tra nạp ảnh 32x32, 20 cửa sổ tiêu biểu & ngẫu nhiên
├── scripts/                    # Scripts tự động hóa chạy mô phỏng
│   ├── run_tests.ps1           # Script PowerShell cho Vivado Simulator
│   └── run_tests.bat           # Script Batch CMD cho Windows
├── docs/                       # Tài liệu thiết kế và đặc tả kỹ thuật
│   ├── stage1_spec.md          # Đặc tả chi tiết Giai đoạn 1
│   ├── stage2_spec.md          # Đặc tả chi tiết Giai đoạn 2 (FSM & Handshake)
│   └── stage3_spec.md          # Đặc tả chi tiết Giai đoạn 3 (RAM Buffers & Sequencer)
├── build/                      # Thư mục tạm chứa log, snapshot và waveform VCD
│   ├── int8_multiplier_waveform.vcd
│   ├── mac_int8_waveform.vcd
│   ├── dot9_int8_waveform.vcd
│   └── conv_window_reader_waveform.vcd
└── README.md                   # Tài liệu hướng dẫn tổng quan dự án
```

---

## 4. Hiện Trạng Giai Đoạn 1: Bộ Nhân INT8 & MAC INT32

Giai đoạn 1 đã được thiết kế và kiểm chứng toàn diện bằng công cụ **Vivado Simulator v2025.1.0**:

### 4.1 Bộ nhân `int8_multiplier`
- **Chức năng**: Nhân hai số signed 8-bit bù hai (`x`, `w`) tạo ra tích signed 16-bit (`product`).
- **Phạm vi giá trị**: $[-128, +127] \times [-128, +127] \to [-16256, +16384]$. Dải 16-bit $[-32768, +32767]$ bảo toàn trọn vẹn giá trị, không tràn bit.
- **Kiểm chứng**: Chạy kiểm tra toàn bộ $256 \times 256 = \mathbf{65,536}$ trường hợp đầu vào. Đối chiếu với mô hình tham chiếu Golden Model.
  - **Kết quả**: `65536 / 65536 PASSED` (0 lỗi).

### 4.2 Khối nhân tích lũy `mac_int8`
- **Chức năng**: Nhân tích lũy với thanh ghi 32-bit, hỗ trợ cờ điều khiển `rst`, `clear`, `valid`.
- **Thứ tự ưu tiên**: `rst` (ưu tiên cao nhất) > `clear` (ưu tiên nhì) > `valid`. Khi `clear` và `valid` cùng bật, hệ thống ưu tiên xóa thanh ghi về 0 và bỏ qua dữ liệu ở chu kỳ đó.
- **Mở rộng dấu (Sign Extension)**: Bit dấu của tích 16-bit (`product[15]`) được nhân bản lên 16 bit cao của toán hạng cộng 32-bit.
- **Kiểm chứng**:
  - Reset đồng bộ và Clear đồng bộ.
  - Xung đột `clear = 1` và `valid = 1`.
  - Toàn bộ các tổ hợp dấu: $(+) \times (+)$, $(+) \times (-)$, $(-) \times (+)$, $(-) \times (-)$, và toán hạng bằng 0.
  - Các giá trị biên: $-128 \times -128 = +16384$; $-128 \times 127 = -16256$; $127 \times 127 = +16129$.
  - Tính năng giữ trạng thái khi có khoảng nghỉ (valid bubble/stall).
  - Kịch bản CNN kernel 9 cặp toán hạng $(-128) \times (-128) \to \mathbf{147,456}$ (Chính xác 100%).
  - Kiểm tra hồi quy 120 chuỗi ngẫu nhiên (seed `32'h20261003`) với độ dài chuỗi từ 1 đến 64 cặp.
  - **Kết quả**: `5826 / 5826 cycle checks PASSED` (0 lỗi).

---

## 5. Hiện Trạng Giai Đoạn 2: FSM & Handshake Wrapper (`dot9_int8`)

Giai đoạn 2 hoàn thành thiết kế lõi tính toán tích chập cơ bản cho kernel $3 \times 3$:

### 5.1 Kiến trúc và Nguyên lý Hoạt động
- **Máy trạng thái FSM 5 trạng thái**: `IDLE` $\to$ `CLEAR` $\to$ `ACCUMULATE` $\to$ `CAPTURE` $\to$ `DONE` $\to$ `IDLE`.
- **Giao thức bắt tay Valid–Ready**: Chỉ nhận toán hạng khi `accept = in_valid && in_ready`. Tín hiệu `in_ready` chỉ tích cực trong `ACCUMULATE` và hạ ngay về 0 sau khi nhận đủ cặp thứ 9 để từ chối tuyệt đối cặp thứ 10.
- **Tránh tranh chấp Nonblocking Assignment (NBA)**: Bổ sung chu kỳ đệm `CAPTURE` để chốt kết quả `result <= mac_acc` sau khi `mac_int8` đã hoàn tất cập nhật tích thứ 9, loại bỏ nguy cơ thiếu tích cuối.
- **Kháng lỗi & Điều khiển**: Bỏ qua xung `start` khi đang `busy = 1`; `done` kéo dài đúng 1 chu kỳ; `result` hợp lệ trong suốt `done = 1` và giữ nguyên đến tác vụ sau hoặc reset; `rst = 1` hủy tác vụ ngay lập tức và không phát `done` giả.

### 5.2 Kết quả Kiểm chứng (`tb_dot9_int8`)
- **Nhóm A (Reset & Khởi động)**: Reset ban đầu, giữ IDLE, từ chối dữ liệu ở IDLE/CLEAR, hủy tác vụ giữa chừng không phát `done` giả $\to$ **PASS**.
- **Nhóm B (Số học & Cực trị)**: Toàn dương, toàn âm, trái dấu, số 0, cực trị CNN $9 \times (-128 \times -128) = \mathbf{147,456}$, chuỗi chỉ có tích thứ 9 khác 0 $\to$ **PASS**.
- **Nhóm C (Handshake, Stall & Backpressure)**: 9 cặp liên tục, stall ngẫu nhiên, stall dài 15 chu kỳ trước cặp thứ 9 không DONE sớm, từ chối cặp thứ 10 $\to$ **PASS**.
- **Nhóm D (Điều khiển & Back-to-Back)**: Bỏ qua `start` khi bận, 5 tác vụ liên tiếp không lẫn dữ liệu, `done` đúng 1 chu kỳ $\to$ **PASS**.
- **Nhóm E (Hồi quy Ngẫu nhiên)**: 120 tác vụ độc lập ngẫu nhiên toán hạng và stall (seed `32'h20261004`) đối chiếu độc lập với Scoreboard 64-bit $\to$ **PASS 120/120**.
- **Tổng kết**: **137 / 137 tác vụ PASSED** (3,727 chu kỳ kiểm tra, 137 xung DONE hợp lệ, 0 lỗi).

---

## 6. Hiện Trạng Giai Đoạn 3: Bộ Đệm RAM & Trích Xuất Cửa Sổ 3x3 (`conv_window_reader`)

Giai đoạn 3 hiện thực bộ nhớ đệm RAM đọc đồng bộ và Sequencer trích xuất cửa sổ $3 \times 3$ cấp cho `dot9_int8`:

### 6.1 Kiến trúc và Nguyên lý Hoạt động
- **Bộ nhớ đệm Input & Weight Buffer**:
  - `Input Buffer`: Lưu $32 \times 32 = 1,024$ phần tử signed INT8 (1,024 bytes), được Vivado tổng hợp suy diễn thành 1 khối **FPGA Block RAM (`RAMB18E1`)**.
  - `Weight Buffer`: Lưu 9 trọng số signed INT8, được tổng hợp suy diễn thành **Distributed RAM (`RAM32M` / `RAM32X1D`)**.
  - Đọc đồng bộ với độ trễ đúng 1 chu kỳ clock (1-Cycle Read Latency).
- **Bộ sinh địa chỉ cửa sổ (Address Generator)**: Tự động tính toán địa chỉ ảnh tuyến tính $addr = (r \ll 5) \ | \ c$ cho 9 phần tử trong cửa sổ $3 \times 3$ tại `(out_row, out_col)` mà không cần dùng bộ nhân phần cứng.
- **Sequencer FSM**: Điều khiển đọc từng cặp toán hạng từ RAM, chờ độ trễ đọc 1 chu kỳ, đưa vào `dot9_int8` qua bắt tay `valid`–`ready`. Khi gặp `in_ready = 0`, Sequencer giữ nguyên `valid = 1` cùng `x, w` ổn định, bảo đảm không đọc vượt, không mất cặp và không nhận trùng dữ liệu.

### 6.2 Kết quả Kiểm chứng (`tb_conv_window_reader`)
- **Nạp dữ liệu mẫu**: 1,024 byte ảnh và 9 byte kernel Sobel-X được nạp thành công qua cổng ghi RAM.
- **Kiểm tra các cửa sổ đại diện theo yêu cầu**:
  - Cửa sổ đầu ảnh `(0, 0)`: 9 cặp khớp 100%, kết quả đạt $-17$ $\to$ **PASS**.
  - Cửa sổ giữa ảnh `(14, 14)`: 9 cặp khớp 100%, kết quả đạt $120$ $\to$ **PASS**.
  - Cửa sổ cuối ảnh `(29, 29)`: 9 cặp khớp 100%, kết quả đạt $184$ $\to$ **PASS**.
  - Cửa sổ góc trên phải `(0, 29)` và góc dưới trái `(29, 0)`: Khớp 100% $\to$ **PASS**.
- **Kiểm tra hồi quy 15 cửa sổ ngẫu nhiên**: Toàn bộ 15 cửa sổ ngẫu nhiên đều tính đúng 100% $\to$ **PASS 15/15**.
- **Tổng kết**: **20 / 20 cửa sổ PASSED** (180 / 180 cặp toán hạng khớp 100% Golden Reference).

### 6.3 Kết quả Tổng hợp Phần cứng (Vivado Synthesis on Artix-7 `xc7a35t`)
- **Block RAM**: **1 $\times$ RAMB18E1** (Input Buffer 8K-bit).
- **Distributed RAM**: **1 $\times$ RAM32M, 2 $\times$ RAM32X1D** (Weight Buffer).
- **Logic Tài nguyên**: 193 LUTs, 144 Flip-Flops (FDRE), 20 CARRY4.
- **Trạng thái**: Hoàn thành không lỗi (**0 Errors, 0 Critical Warnings**).

---

## 7. Hướng Dẫn Chạy Kiểm Tra (Verification)

Môi trường kiểm tra sử dụng công cụ **Vivado Simulator 2025.1** có sẵn trên máy.

### Cách 1: Chạy tự động bằng PowerShell (Khuyên dùng)
Mở cửa sổ PowerShell và thực thi lệnh:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1
```
*Script tự động biên dịch và chạy cả 4 bài test:*
1. `tb_int8_multiplier` (65,536 test vectors)
2. `tb_mac_int8` (5,826 cycle checks)
3. `tb_dot9_int8` (137 tasks, 3,727 cycle checks)
4. `tb_conv_window_reader` (20 windows, 180 pair checks)

### Cách 2: Chạy bằng Command Prompt (Batch script)
Nhấp đúp chuột vào file `scripts\run_tests.bat` hoặc mở cmd gõ:
```cmd
.\scripts\run_tests.bat
```

### Cách 3: Xem dạng sóng Waveform
Sau khi chạy kiểm tra, 4 file waveform dạng VCD được tạo trong thư mục `build/`:
- `build/int8_multiplier_waveform.vcd`
- `build/mac_int8_waveform.vcd`
- `build/dot9_int8_waveform.vcd`
- `build/conv_window_reader_waveform.vcd`

Người dùng có thể mở bằng công cụ **GTKWave** hoặc nhập trực tiếp vào Vivado Waveform Viewer.

---

## 8. Kế Hoạch Cho Bước Tiếp Theo (Giai Đoạn 4)

Sau khi hoàn thành bộ đệm RAM và khối trích xuất cửa sổ `conv_window_reader`, bước tiếp theo sẽ xây dựng:
1. **Bộ điều khiển quét toàn bộ bức ảnh (2D Convolution Raster Scanner)**:
   - Tự động sinh tọa độ quét `(out_row, out_col)` từ `(0, 0)` đến `(29, 29)` cho đủ $30 \times 30 = 900$ pixel output.
   - Quản lý bộ đệm kết quả đầu ra (Output Buffer $30 \times 30 = 900$ bytes).
2. **Đối chiếu toàn diện với Golden Model Python**:
   - Viết script Python sinh ma trận ảnh đầu vào, ma trận trọng số, tính toán ma trận đầu ra chuẩn.
   - So sánh tự động từng pixel giữa kết quả RTL simulation và file kết quả Python.
