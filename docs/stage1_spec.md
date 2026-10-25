# ĐẶC TẢ KỸ THUẬT GIAI ĐOẠN 1: BỘ NHÂN SIGNED INT8 VÀ MAC INT32

Tài liệu này mô tả chi tiết kiến trúc phần cứng, giao tiếp, đặc tả chu kỳ và cơ chế xác thực cho hai khối RTL nền tảng: `int8_multiplier` và `mac_int8`.

---

## 1. Khối nhân `int8_multiplier`

### 1.1 Sơ đồ khối và Giao tiếp
Module thực hiện phép nhân số học bù hai có dấu giữa hai toán hạng 8-bit.

```
                  +---------------------+
   x[7:0] (INT8)  |                     |
  --------------->|   int8_multiplier   |---> product[15:0] (INT16)
   w[7:0] (INT8)  |     (Combinational) |
  --------------->|                     |
                  +---------------------+
```

| Tín hiệu | Hướng | Độ rộng | Kiểu dữ liệu | Mô tả |
|---|---|---|---|---|
| `x` | Input | 8 bit | `logic signed [7:0]` | Toán hạng thứ nhất (Pixel / Activation) |
| `w` | Input | 8 bit | `logic signed [7:0]` | Toán hạng thứ hai (Weight / Kernel) |
| `product` | Output | 16 bit | `logic signed [15:0]` | Tích số học đầy đủ của `x * w` |

### 1.2 Phân tích độ rộng và bảo toàn bit
- Dải biểu diễn của số nguyên bù hai 8-bit (`signed [7:0]`):
  $$\text{Dải giá trị} = [-2^{7}, 2^7 - 1] = [-128, +127]$$
- Hai trường hợp cực trị của tích:
  1. Cực trị âm: $(-128) \times (+127) = -16,256$ (biểu diễn hex 16-bit: `16'hC080`).
  2. Cực trị dương: $(-128) \times (-128) = +16,384$ (biểu diễn hex 16-bit: `16'h4000`).
- Biểu diễn của số nguyên bù hai 16-bit (`signed [15:0]`):
  $$\text{Dải giá trị} = [-2^{15}, 2^{15} - 1] = [-32,768, +32,767]$$
- **Kết luận**: Cả hai cực trị $-16,256$ và $+16,384$ đều nằm hoàn toàn bên trong giới hạn $[-32,768, +32,767]$. Do đó, đầu ra 16-bit **bảo toàn 100% độ chính xác**, hoàn toàn không bị tràn bit hay mất mát thông tin.

---

## 2. Khối nhân - tích lũy `mac_int8`

### 2.1 Sơ đồ kiến trúc phần cứng

```
                  +-------------------------------------------------------------+
                  | mac_int8                                                    |
                  |                                                             |
   x[7:0] ------->|  +-----------------+                                        |
                  |  | int8_multiplier |                                        |
   w[7:0] ------->|  |   (x * w)       |                                        |
                  |  +--------+--------+                                        |
                  |           | product[15:0]                                   |
                  |           v                                                 |
                  |     Sign Extension ({{16{product[15]}}, product})           |
                  |           |                                                 |
                  |           | product_ext[31:0]                               |
                  |           v                                                 |
                  |         +---+                                               |
                  |         | + |<--------------------------+                   |
                  |         +---+                           |                   |
                  |           |                             |                   |
                  |           v (sum_next)                  |                   |
                  |     +-----------+                       |                   |
   clk ---------->|     |           |                       |                   |
   rst ---------->|====>|  acc[31:0]|======================>+====> acc[31:0]    |
   clear -------->|     | (Reg 32b) |                                           |
   valid -------->|     +-----------+                                           |
                  +-------------------------------------------------------------+
```

### 2.2 Bảng tín hiệu giao tiếp

| Tín hiệu | Hướng | Độ rộng | Kiểu | Mô tả chức năng |
|---|---|---|---|---|
| `clk` | Input | 1 bit | `logic` | Xung đồng hồ hệ thống (cạnh lên kích hoạt) |
| `rst` | Input | 1 bit | `logic` | Reset đồng bộ, mức tích cực cao (active-high). Ưu tiên cao nhất |
| `clear` | Input | 1 bit | `logic` | Xóa đồng bộ accumulator về 0, active-high. Ưu tiên thứ hai |
| `valid` | Input | 1 bit | `logic` | Báo dữ liệu đầu vào `x`, `w` hợp lệ cần tích lũy |
| `x` | Input | 8 bit | `logic signed [7:0]` | Toán hạng đầu vào (pixel/activation) |
| `w` | Input | 8 bit | `logic signed [7:0]` | Toán hạng đầu vào (kernel weight) |
| `acc` | Output | 32 bit | `logic signed [31:0]` | Giá trị tổng tích lũy đầu ra |

---

## 3. Bản chất các quyết định thiết kế phần cứng

### 3.1 Vì sao Accumulator sử dụng 32 bit?
Trong mạng nơ-ron tích chập (CNN), một phần tử output được tính bằng tích chập của ma trận trọng số $K \times K$ với các kênh đầu vào $C_{in}$:
$$Y = \text{Bias} + \sum_{c=1}^{C_{in}} \sum_{i=1}^{K} \sum_{j=1}^{K} X(c, i, j) \cdot W(c, i, j)$$

- Với kernel $3 \times 3$ đơn kênh ban đầu: số phép nhân tích lũy là $9$.
  - Cực trị dương tối đa: $9 \times (+16,384) = +147,456$.
  - Cực trị âm tối đa: $9 \times (-16,256) = -146,304$.
  - Khoảng này cần ít nhất 19 bit signed ($-262,144$ đến $+262,143$).
- Khi mở rộng sang mạng nhiều kênh ($C_{in} = 32, 64, 128$):
  - Số phép tích lũy có thể lên tới $9 \times 128 = 1,152$ phép tính.
  - Tổng cực trị: $1,152 \times 16,384 \approx 18.87 \times 10^6$.
  - Cần ít nhất 26 bit signed.
- Thanh ghi **32-bit signed** biểu diễn được từ $-2,147,483,648$ đến $+2,147,483,647$ ($\approx \pm 2.14 \times 10^9$):
  - Khớp trực tiếp với thanh ghi đa năng (GPR) 32-bit của kiến trúc CPU RISC-V 32-bit (RV32I).
  - Cho phép CPU đọc kết quả qua bus 32-bit chỉ trong **1 chu kỳ bus** duy nhất mà không cần ghép word.
  - Ngăn ngừa hoàn toàn nguy cơ tràn số trong suốt quá trình tích lũy toàn bộ ma trận kernel.

### 3.2 Sign Extension (Mở rộng dấu) làm gì?
- Tích `product` có độ rộng 16-bit bù hai. Khi đưa vào bộ cộng 32-bit cùng với `acc[31:0]`, nếu không mở rộng dấu, các bit từ 16 đến 31 sẽ bị điền số 0 (Zero Extension), khiến số âm bị hiểu nhầm thành số dương cực lớn.
  *Ví dụ*: Số $-1$ dạng 16-bit là `0xFFFF`. Nếu zero-extend lên 32-bit thành `0x0000FFFF` ($+65,535$), giá trị số học bị sai lệch hoàn toàn.
- **Giải pháp phần cứng**: Mở rộng dấu bằng cách nhân bản bit dấu (MSB: `product[15]`) lên 16 bit cao:
  $$\text{product\_ext} = \{\{16\{\text{product}[15]\}\}, \text{product}[15:0]\}$$
  Khi đó `0xFFFF` ($-1$) được mở rộng thành `0xFFFFFFFF` ($-1$), bảo toàn chính xác giá trị số học bù hai.

### 3.3 Vì sao dùng Nonblocking Assignment (`<=`) cho Accumulator?
- Trong SystemVerilog/Verilog, thanh ghi phần cứng (Flip-Flop) cập nhật trạng thái tại sườn xung đồng hồ `posedge clk`.
- Nếu sử dụng blocking assignment (`=`):
  Thứ tự thực thi trong simulation có thể dẫn đến hiện tượng race condition (tranh chấp dữ liệu giữa các khối tuần tự hoặc giữa testbench và DUT).
- Khi sử dụng nonblocking assignment (`<=`):
  Trình mô phỏng lập lịch gán giá trị vào vùng sự kiện **NBA (Nonblocking Assignment Update Region)** sau khi tất cả các biểu thức bên vế phải (RHS) đã được tính toán ở vùng **Active Region**. Điều này phản ánh chính xác hành vi vật lý của D-Flip-Flop trong silic: giá trị cũ tại đầu vào D được chốt tại cạnh xung clock và xuất hiện ở đầu ra Q sau một khoảng trễ lan truyền $t_{cq}$.

### 3.4 Logic điều khiển và thứ tự ưu tiên
Thứ tự ưu tiên tại mỗi cạnh lên `posedge clk`:
$$\mathbf{rst} > \mathbf{clear} > \mathbf{valid}$$

1. **Khi `rst = 1`**: `acc <= 32'sd0;` (Bất kể trạng thái của `clear`, `valid` hay `x, w`).
2. **Khi `rst = 0, clear = 1`**: `acc <= 32'sd0;`
   - *Trường hợp đặc biệt*: Nếu `clear = 1` và `valid = 1` xảy ra cùng một chu kỳ, phần cứng **chỉ thực hiện xóa tổng**, dữ liệu tại `x, w` bị bỏ qua và không được tích lũy vào chu kỳ này.
3. **Khi `rst = 0, clear = 0, valid = 1`**: `acc <= acc + product_ext;` (Nhận toán hạng và cộng dồn).
4. **Khi `rst = 0, clear = 0, valid = 0`**: `acc` giữ nguyên giá trị (Hold state).

### 3.5 Hành vi tràn số (Overflow Behavior)
Phép cộng 32-bit tuân theo luật số học bù hai mod $2^{32}$ (wrap-around tự nhiên). Nếu tổng vượt quá $[ -2^{31}, 2^{31}-1 ]$, các bit tràn phía trên bit 31 sẽ bị cắt bỏ mà không gây treo hệ thống. Đối với các tác vụ tích chập thông thường, tổng giá trị nhỏ hơn rất nhiều so với $2^{31}-1$ nên hiện tượng wrap không xảy ra.

---

## 4. Bảng diễn tiến qua các cạnh clock cho chuỗi mẫu

Bảng sau minh họa trạng thái tín hiệu qua từng chu kỳ xung clock ($T_0 \to T_8$):

| Chu kỳ | rst | clear | valid | x | w | product (16b) | product_ext (32b) | acc (sau posedge) | Ghi chú hành vi |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| $T_0$ | 1 | 0 | 0 | 0 | 0 | 0 | 0 | **0** | Reset hệ thống |
| $T_1$ | 0 | 0 | 1 | +10 | +20 | +200 | +200 | **+200** | Phép tính 1: $0 + 200 = 200$ |
| $T_2$ | 0 | 0 | 1 | -15 | +10 | -150 | -150 | **+50** | Phép tính 2: $200 + (-150) = 50$ |
| $T_3$ | 0 | 0 | 0 | +99 | +99 | +9801 | +9801 | **+50** | **Valid Bubble (Stall)**: acc giữ nguyên |
| $T_4$ | 0 | 0 | 1 | -128 | -128 | +16384 | +16384 | **+16434** | Cực trị âm: $50 + 16384 = 16434$ |
| $T_5$ | 0 | 1 | 1 | +50 | +10 | +500 | +500 | **0** | **Clear & Valid cùng bật**: Clear thắng, acc về 0 |
| $T_6$ | 0 | 0 | 1 | +7 | +8 | +56 | +56 | **+56** | Bắt đầu tích lũy chuỗi mới |
| $T_7$ | 0 | 0 | 1 | +127 | -128 | -16256 | -16256 | **-16200** | Cực trị trái dấu: $56 - 16256 = -16200$ |
| $T_8$ | 1 | 0 | 1 | +10 | +10 | +100 | +100 | **0** | Reset đột ngột giữa chừng |

---

## 5. Kết quả kiểm chứng thực nghiệm

Hai testbench tự kiểm tra đã được chạy trực tiếp bằng Vivado Simulator v2025.1.0:

1. **`tb_int8_multiplier` (Exhaustive)**:
   - Tổng số vector kiểm tra: **65,536 / 65,536** tổ hợp đầu vào signed 8-bit.
   - Số lỗi phát hiện: **0** (Mismatch = 0).
   - Kết quả: **PASS 100%**.

2. **`tb_mac_int8` (Chu kỳ chi tiết & Ngẫu nhiên)**:
   - Số lượt kiểm tra trạng thái thanh ghi theo chu kỳ: **5,826 chu kỳ**.
   - Kiểm tra reset, clear, ưu tiên clear > valid, các giá trị biên $-128, +127$.
   - Kiểm tra chuỗi 9 cặp CNN $(-128) \times (-128)$: Kết quả đạt chính xác **147,456**.
   - Kiểm tra hồi quy 120 chuỗi ngẫu nhiên (seed `32'h20261003`) kèm các chu kỳ stall (valid bubble).
   - Số lỗi phát hiện: **0**.
   - Kết quả: **PASS 100%**.
