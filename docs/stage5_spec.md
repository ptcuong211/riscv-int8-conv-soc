# TÀI LIỆU ĐẶC TẢ KỸ THUẬT VÀ THIẾT KẾ STAGE 5 (STAGE 5 SPECIFICATION)
## Output Buffer & Convolution Accelerator Top Integration

**Dự án:** RISC-V SoC tích hợp bộ tăng tốc Convolution INT8 trên FPGA  
**Đối tượng:** Sinh viên ngành Kỹ thuật Máy tính / Điện tử - Thiết kế Vi mạch RTL  
**Workspace:** `D:\DA2\SoC RISCV`  
**Target FPGA:** Xilinx Artix-7 `xc7a35tcpg236-1` (Basys 3 / tương đương)  
**Tần số hoạt động mục tiêu:** 100 MHz (Period: 10.000 ns)  
**Ngày hoàn thành:** 31/10/2026  

---

## 1. Mục Tiêu Giai Đoạn 5 (Stage 5 Objectives)

Trong Giai đoạn 4, module `conv2d_raster_scanner` đã thực hiện thành công việc quét toàn bộ ảnh ma trận đặc trưng $32 \times 32$ với kernel $3 \times 3$ và sinh ra dòng dữ liệu 900 kết quả tích chập theo cơ chế bắt tay Streaming (`result_valid` / `result_ready`).

Mục tiêu cốt lõi của Giai đoạn 5 là:
1. **Thiết kế module `output_buffer`**: Cung cấp bộ đệm lưu trữ nội bộ dung lượng 900 từ 32-bit (signed INT32, tổng cộng 28,800 bit = 3,600 byte), suy luận trực tiếp thành Block RAM phần cứng trên FPGA (BRAM).
2. **Ghép nối luồng dữ liệu (Dataflow Coupling)**: Kết nối ngõ ra streaming của `conv2d_raster_scanner` vào cổng ghi của `output_buffer` mà không làm rơi kết quả, không ghi đè và bảo đảm thứ tự địa chỉ Raster Scan tuần tự ($0 \to 899$).
3. **Đóng gói Top-Level Accelerator (`conv_accelerator_top`)**: Gom toàn bộ phân cấp phần cứng từ Giai đoạn 1 đến Giai đoạn 5 thành một module duy nhất, đóng vai trò một IP core hoàn chỉnh chuẩn bị tích hợp vào Bus SoC ở Stage tiếp theo.
4. **Cung cấp giao tiếp điều khiển và nạp/đọc dữ liệu**:
   - Nạp Input Buffer (1024 bytes signed INT8).
   - Nạp Weight Buffer (9 bytes signed INT8).
   - Điều khiển chạy: `start`, theo dõi `busy` và `done`.
   - Đọc kết quả từ Output Buffer thông qua cổng đọc đồng bộ 1 chu kỳ clock.
5. **Kiểm chứng độc lập và toàn diện**:
   - Viết testbench tự kiểm tra `tb_output_buffer` và `tb_conv_accelerator_top`.
   - Chạy kiểm thử hồi quy 7/7 testbench đạt 100% PASS.
   - Chạy Vivado Synthesis & Implementation đạt timing 100 MHz thực tế trên chip Artix-7.

---

## 2. Kiến Trúc Tổng Thể Accelerator Top (`conv_accelerator_top`)

Module `conv_accelerator_top` đóng gói toàn bộ phân cấp tính toán của bộ tăng tốc tích chập 2D:

```text
                               conv_accelerator_top
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  clk, rst, start ----------> [ Control Logic ] ----------> busy, done             |
|                                                                                   |
|  ibuf_wr_en, addr, data ---> +-----------------------------+                      |
|                              |    conv2d_raster_scanner    |                      |
|  wbuf_wr_en, addr, data ---> |  +-----------------------+  |                      |
|                              |  |  conv_window_reader   |  |                      |
|                              |  |  - Input Buffer BRAM  |  |                      |
|                              |  |  - Weight Buffer LUT  |  |                      |
|                              |  |  - Datapath dot9_int8 |  |                      |
|                              |  +-----------------------+  |                      |
|                              +-----------------------------+                      |
|                                             |                                     |
|                               result_valid  |  result_ready = 1                   |
|                               result_addr   |                                     |
|                               result_data   v                                     |
|                              +-----------------------------+                      |
|                              |        output_buffer        | <--- obuf_rd_addr    |
|                              |    (900 x 32-bit BRAM)      | ---> obuf_rd_data    |
|                              +-----------------------------+                      |
|                                                                                   |
+-----------------------------------------------------------------------------------+
```

### Phân cấp module (Design Hierarchy):
- `conv_accelerator_top` (Stage 5 Top)
  - `conv2d_raster_scanner` (Stage 4 Scanner & Controller)
    - `conv_window_reader` (Stage 3 Window Extractor & Datapath Sequencer)
      - `ram_sync_read` (`u_input_buffer`: 1024x8-bit BRAM RAMB18E1)
      - `ram_sync_read` (`u_weight_buffer`: 9x8-bit Distributed LUTRAM)
      - `dot9_int8` (Stage 2 Datapath Dot Product)
        - `mac_int8` (Stage 1 Accumulator)
          - `int8_multiplier` (Stage 1 Multiplier)
  - `output_buffer` (`u_output_buffer`: 900x32-bit BRAM RAMB36E1)

---

## 3. Vai Trò Của Output Buffer

Trong kiến trúc bộ tăng tốc phần cứng:
- Scanner sinh kết quả phân tán theo thời gian (cứ sau mỗi ~30 chu kỳ tính một cửa sổ 3x3 thì xuất một kết quả 32-bit).
- Nếu không có Output Buffer, CPU hoặc bộ điều khiển DMA bên ngoài sẽ phải liên tục thăm dò hoặc bị khóa cứng theo chu kỳ xuất kết quả của bộ tăng tốc.
- `output_buffer` đóng vai trò là **bộ nhớ đệm kết quả cục bộ**:
  - Tự động tiếp nhận và ghi nhớ toàn bộ 900 kết quả ($30 \times 30$) theo địa chỉ tuyến tính $0 \to 899$.
  - Giải phóng bộ tăng tốc sau khi quét xong: toàn bộ kết quả đã sẵn sàng để CPU đọc bất cứ lúc nào qua cổng đọc đọc ngẫu nhiên (Random Access).
  - Phù hợp hoàn hảo để ánh xạ vào không gian địa chỉ bộ nhớ (Memory-Mapped I/O - MMIO) của hệ thống SoC ở Stage sau.

---

## 4. Đặc Tả Giao Diện (Module Interface)

### 4.1. Module `output_buffer.sv`

```systemverilog
module output_buffer #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 900,
    parameter int ADDR_WIDTH = 10,
    parameter     RAM_STYLE  = "block"
) (
    input  logic                          clk,

    // Cổng ghi đồng bộ (Write Port)
    input  logic                          wr_en,
    input  logic [ADDR_WIDTH-1:0]         wr_addr,
    input  logic signed [DATA_WIDTH-1:0]  wr_data,

    // Cổng đọc đồng bộ (Read Port)
    input  logic [ADDR_WIDTH-1:0]         rd_addr,
    output logic signed [DATA_WIDTH-1:0]  rd_data
);
```

### 4.2. Module `conv_accelerator_top.sv`

| Tên cổng | Hướng | Độ rộng | Kiểu dữ liệu | Ý nghĩa |
|---|:---:|:---:|:---:|---|
| `clk` | In | 1 | `logic` | Xung nhịp hệ thống 100 MHz |
| `rst` | In | 1 | `logic` | Reset đồng bộ, tích cực mức cao (Active-High) |
| `start` | In | 1 | `logic` | Xung kích hoạt quét toàn bộ ảnh (tích cực 1 chu kỳ) |
| `busy` | Out | 1 | `logic` | Mức 1 khi Accelerator đang bận tính toán hoặc ghi dữ liệu |
| `done` | Out | 1 | `logic` | Xung 1 chu kỳ báo toàn bộ 900 kết quả đã ghi xong |
| `ibuf_wr_en` | In | 1 | `logic` | Cho phép ghi Input Buffer (Feature Map) |
| `ibuf_wr_addr`| In | 10 | `logic [9:0]` | Địa chỉ byte ảnh ($0 \to 1023$) |
| `ibuf_wr_data`| In | 8 | `logic signed [7:0]` | Dữ liệu pixel (signed INT8) |
| `wbuf_wr_en` | In | 1 | `logic` | Cho phép ghi Weight Buffer (Kernel) |
| `wbuf_wr_addr`| In | 4 | `logic [3:0]` | Địa chỉ trọng số kernel ($0 \to 8$) |
| `wbuf_wr_data`| In | 8 | `logic signed [7:0]` | Dữ liệu trọng số (signed INT8) |
| `obuf_rd_addr`| In | 10 | `logic [9:0]` | Địa chỉ đọc Output Buffer ($0 \to 899$) |
| `obuf_rd_data`| Out | 32 | `logic signed [31:0]`| Kết quả tích chập đọc ra (signed INT32) |

---

## 5. Luồng Xử Lý (Operational Workflow)

Một chu trình tính toán hoàn chỉnh diễn ra như sau:
1. **Khởi tạo / Reset**: Đưa `rst = 1` trong ít nhất 1 chu kỳ clock để đưa FSM về `STATE_IDLE`. Lúc này `busy = 0`, `done = 0`.
2. **Nạp ảnh (Load Feature Map)**: Master ngoài kích hoạt `ibuf_wr_en = 1`, ghi tuần tự 1024 bytes dữ liệu vào địa chỉ $0 \to 1023$ của Input Buffer.
3. **Nạp trọng số (Load Kernel)**: Master ngoài kích hoạt `wbuf_wr_en = 1`, ghi tuần tự 9 bytes trọng số vào địa chỉ $0 \to 8$ của Weight Buffer.
4. **Phát lệnh khởi động**: Phát xung `start = 1` trong 1 chu kỳ.
5. **Quét tự động**: `conv2d_raster_scanner` kích hoạt, `busy` chuyển lên mức 1:
   - FSM lần lượt điều khiển trích xuất 900 cửa sổ $3 \times 3$ từ tọa độ $(0, 0)$ đến $(29, 29)$.
   - `dot9_int8` tính tích chập 9 phần tử.
   - Mỗi kết quả sinh ra được chuyển qua giao thức streaming với địa chỉ tuyến tính tương ứng.
6. **Lưu kết quả**: `output_buffer` tiếp nhận ngay lập tức từng kết quả hợp lệ (`wr_en = scanner_result_valid`) và ghi vào ô nhớ tương ứng.
7. **Báo hoàn tất**: Sau khi kết quả thứ 900 (tại địa chỉ 899) được ghi hoàn tất vào BRAM, accelerator phát xung `done = 1` trong đúng 1 chu kỳ clock. Sau đó `busy` hạ về 0.
8. **Đọc kết quả**: Phía đọc (CPU/Testbench) cấp địa chỉ $0 \to 899$ vào `obuf_rd_addr` để lấy dữ liệu qua `obuf_rd_data`.

---

## 6. Cách Ghi 900 Kết Quả Vào Output Buffer

Cơ chế kết nối giữa `conv2d_raster_scanner` và `output_buffer`:
```systemverilog
assign scanner_result_ready = 1'b1;

output_buffer #(
    .DATA_WIDTH (32),
    .DEPTH      (TOTAL_OUTPUTS),
    .ADDR_WIDTH (10),
    .RAM_STYLE  ("block")
) u_output_buffer (
    .clk     (clk),
    .wr_en   (scanner_result_valid && scanner_result_ready),
    .wr_addr (scanner_result_addr),
    .wr_data (scanner_result_data),
    .rd_addr (obuf_rd_addr),
    .rd_data (obuf_rd_data)
);
```

### Tính chính xác về thời gian ghi (Timing Analysis):
- Khi scanner hoàn tất tính toán cửa sổ $(r, c)$, FSM chuyển sang `STATE_OUTPUT_RESULT`.
- Tại chu kỳ $T$: `result_valid = 1`, `result_addr = r * 30 + c`, `result_data = window_result`.
- Cổng ghi của BRAM nhận `wr_en = 1`.
- Tại cạnh lên clock tiếp theo ($T \to T+1$): BRAM ghi dữ liệu vào địa chỉ `result_addr`.
- Đối với phần tử cuối cùng (địa chỉ 899 tại tọa độ $29, 29$):
  - Chu kỳ $T_{899}$: Handshake diễn ra.
  - Chu kỳ $T_{899}+1$: Kết quả 899 đã nằm trọn vẹn trong RAM; scanner chuyển sang `STATE_DONE` và phát xung `done = 1`.
  - Do đó: **Không bao giờ xảy ra tình trạng phát `done` trước khi phần tử thứ 900 được lưu an toàn.**

---

## 7. Cách Đọc Output Buffer & Synchronous Read Latency

### Độ trễ đọc đồng bộ (1-Cycle Latency):
Module `output_buffer` sử dụng cấu trúc Block RAM đồng bộ chuẩn FPGA:
- **Chu kỳ $N$**: Phía ngoài đặt địa chỉ cần đọc lên `obuf_rd_addr`.
- **Cạnh lên clock $N \to N+1$**: BRAM giải mã địa chỉ và chốt dữ liệu từ mảng nhớ vào thanh ghi ngõ ra `rd_data`.
- **Chu kỳ $N+1$**: Dữ liệu hợp lệ xuất hiện ổn định tại `obuf_rd_data`.

### Kỹ thuật đọc dạng đường ống (Pipelined Reading):
Để đọc toàn bộ 900 từ một cách nhanh nhất (chỉ mất $900 + 1 = 901$ chu kỳ):
```systemverilog
obuf_rd_addr <= 10'd0;
@(posedge clk); // Đặt địa chỉ 0

for (int i = 0; i < 900; i++) begin
    if (i + 1 < 900) obuf_rd_addr <= 10'(i + 1); // Cấp trước địa chỉ i+1
    #1; // Lấy mẫu obuf_rd_data tương ứng với địa chỉ i
    // Sử dụng obuf_rd_data tại đây
    @(posedge clk);
end
```

---

## 8. Kết Quả Kỹ Thuật Tổng Hợp & Định Tuyến (FPGA Implementation)

Tổng hợp trên phần cứng thực tế AMD/Xilinx Artix-7 `xc7a35tcpg236-1` tại tần số 100 MHz (Vivado 2025.1):

### 8.1. Bảng Tiêu Thụ Tài Nguyên Phần Cứng

| Tài nguyên phần cứng | Sử dụng (Used) | Khả dụng (Available) | Tỷ lệ sử dụng (%) | Ghi chú kiến trúc |
|---|:---:|:---:|:---:|---|
| **Slice LUTs** | **190** | 20,800 | **0.91%** | 184 Logic LUTs + 6 LUTRAMs |
| - LUT as Logic | 184 | 20,800 | 0.88% | FSM, Adder tree, Multiplier logic |
| - LUT as Memory | 6 | 9,600 | 0.06% | Weight Buffer (9 bytes LUTRAM) |
| **Slice Registers (FF)** | **199** | 41,600 | **0.48%** | 100% đồng bộ (FDRE) |
| **Block RAM (BRAM Tile)**| **1.5** | 50 | **3.00%** | Gồm 1 RAMB36E1 + 1 RAMB18E1 |
| - RAMB36E1 | 1 | 50 | 2.00% | **Output Buffer (900x32-bit = 28.8Kb)** |
| - RAMB18E1 | 1 | 100 | 1.00% | **Input Buffer (1024x8-bit = 8.19Kb)** |
| **DSPs (DSP48E1)** | **0** | 90 | **0.00%** | Tối ưu diện tích, bộ nhân dùng LUT |
| **Clock Buffers (BUFG)**| **1** | 32 | **3.13%** | Phân phối clock toàn cục |

### 8.2. Giải Thích Vì Sao Tài Nguyên BRAM Tăng So Với Stage 4
- Ở Stage 4, hệ thống chỉ có `u_input_buffer` dung lượng $1024 \times 8 = 8,192$ bit, vừa vặn nằm trong **1 khối RAMB18E1** (dung lượng tối đa 18 Kb).
- Ở Stage 5, bổ sung thêm `output_buffer` dung lượng $900 \times 32 = 28,800$ bit. Một khối RAMB18E1 không đủ chứa, do đó Vivado tự động suy luận và map vào **1 khối RAMB36E1** (dung lượng 36 Kb, cấu hình $1024 \times 32$-bit hoặc $1024 \times 36$-bit).
- Tổng tài nguyên BRAM là $1.0\text{ (RAMB36)} + 0.5\text{ (RAMB18)} = 1.5\text{ BRAM Tiles}$, cực kỳ tiết kiệm và tối ưu.

### 8.3. Báo Cáo Phân Tích Định Thời (Timing Analysis at 100 MHz)

| Tiêu chí định thời | Giá trị thực tế | Ngưỡng yêu cầu | Kết luận |
|---|:---:|:---:|:---:|
| Chu kỳ xung nhịp ($T_{\text{clk}}$) | **10.000 ns** | 10.000 ns (100 MHz) | ĐẠT |
| Worst Negative Slack (WNS) | **+0.271 ns** | $\ge 0.000\text{ ns}$ | **PASS** (Slack dương) |
| Total Negative Slack (TNS) | **0.000 ns** | $0.000\text{ ns}$ | **PASS** (0 failing path) |
| Worst Hold Slack (WHS) | **+0.055 ns** | $\ge 0.000\text{ ns}$ | **PASS** |
| Total Hold Slack (THS) | **0.000 ns** | $0.000\text{ ns}$ | **PASS** |
| Worst Pulse Width Slack (WPWS) | **+3.750 ns** | $\ge 0.000\text{ ns}$ | **PASS** |
| Timing Status | **MET** | Không vi phạm Setup / Hold | **PASS 100%** |

---

## 9. Hạn Chế Hiện Tại & Bước Sang Giai Đoạn 6

### Hạn chế ở Stage 5:
- Chưa tích hợp CPU RISC-V (PicoRV32).
- Các cổng nạp `ibuf_wr_*`, `wbuf_wr_*` và đọc `obuf_rd_*` hiện là các chân song song trực tiếp, chưa được ghép qua bus MMIO (Memory-Mapped I/O).
- Cần một bộ giải mã địa chỉ chuẩn (Address Decoder) để CPU có thể truy cập các thanh ghi điều khiển (`CR_START`, `SR_STATUS`) và các vùng đệm bộ nhớ thông qua các lệnh `lw` / `sw`.

### Kế hoạch Giai đoạn 6 (Stage 6 Preview):
- Tích hợp vi điều khiển **PicoRV32** vào SoC.
- Thiết kế **MMIO Interconnect / Bus Controller** để ánh xạ:
  - Base Address `0x8000_0000`: Control/Status Registers (`START`, `BUSY`, `DONE`).
  - Base Address `0x8000_1000`: Input Buffer (1024 bytes).
  - Base Address `0x8000_2000`: Weight Buffer (9 bytes).
  - Base Address `0x8000_3000`: Output Buffer (900 words / 3600 bytes).
- Viết chương trình firmware C chạy trên PicoRV32 điều khiển toàn bộ Accelerator và xuất kết quả qua UART.

