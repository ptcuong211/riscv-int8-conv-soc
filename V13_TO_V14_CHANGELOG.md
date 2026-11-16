# BÁO CÁO NHẬT KÝ THAY ĐỔI: V13 → V14 (V13_TO_V14_CHANGELOG)
## Đồ án 2: Thiết kế và Hiện thực RTL Hệ thống RISC-V SoC với Bộ tăng tốc Tích chập 2D INT8 trên FPGA Artix-7

- **Ngày hoàn thành:** 16/11/2026
- **Workspace:** `D:\DA2\SoC RISCV`
- **Git Branch:** `fix/f03-verification`
- **Git Commit HEAD:** `c40f793` (*test(dv): improve coverage with non-homogeneous signed matrices, boundary checks, and invalid MMIO bus tests*)
- **Target Hardware:** Digilent Basys 3 FPGA Trainer Board (`xc7a35tcpg236-1`) — Single Clock Domain 100.000 MHz
- **Tài liệu nguồn chuyển đổi:** `Bao_Cao_Do_An_2_V13.docx`
- **Tài liệu xuất bản chính thức:** `Bao_Cao_Do_An_2_V14.docx` & `Bao_Cao_Do_An_2_V14.pdf`

---

## 1. MỤC TIÊU VÀ BỐI CẢNH NÂNG CẤP PHIÊN BẢN V14

Phiên bản V14 là bản hoàn thiện kỹ thuật tối hậu của Thuyết minh Đồ án 2, phản ánh trung thực và toàn diện các kết quả đã được hiện thực, kiểm chứng và đóng gói qua 3 giai đoạn sửa lỗi trọng yếu (F-01, F-02, F-03) cùng kết quả kiểm định độc lập của **Gemini 4 Argon High**:

1. **Khắc phục triệt để lỗi vi phạm DRC REQP-1839 (F-01):** Bổ sung mạch đồng bộ reset 2 tầng FF nội bộ với thuộc tính `ASYNC_REG = "TRUE"` trong `soc_ram.sv`, đưa số cảnh báo DRC từ 12 về đúng 0 cảnh báo.
2. **Khắc phục lỗi máy trạng thái UART FSM (F-02):** Tách độc lập tín hiệu phát `BOOT: SoC OK` ngay khi xả reset, bổ sung bắt tay 2 nhịp chống nhả cờ `busy` sớm, truyền trọn vẹn 57/57 bytes ASCII chuẩn xác 100%.
3. **Nâng cao độ phủ kiểm chứng vi mạch (F-03):** Bổ sung ma trận signed INT8 $[-128, +127]$ phi đồng nhất, kernel bất đối xứng, đối chiếu 900/900 kết quả với mô hình Golden Reference độc lập, kiểm tra nghiêm ngặt tọa độ biên Head/Mid/Tail, và tiêm lỗi truy cập bus MMIO không hợp lệ (`0xDEADBEEF`, 1-cycle ready, không treo bus).
4. **Chuẩn hóa thông số thực thi Vivado 2025.1:** Đồng bộ toàn bộ các bảng tài nguyên, thời gian tĩnh STA và DRC với báo cáo thực tế mới nhất sau Phase 3G.
5. **Rà soát và tài liệu hóa các Finding gốc F-04 đến F-09:** Phân định ranh giới kỹ thuật rõ ràng giữa phạm vi hoàn thành của Đồ án 2 và định hướng mở rộng cho Đồ án Tốt nghiệp (Capstone).

---

## 2. BẢNG TỔNG HỢP THAY ĐỔI CHỈ SỐ KỸ THUẬT (V13 VS V14)

| Chỉ số / Hạng mục Kỹ thuật | Báo cáo V13 (Cũ) | Báo cáo V14 (Chính thức) | Căn cứ Kỹ thuật Xác minh |
| :--- | :---: | :---: | :--- |
| **Cảnh báo DRC REQP-1839** | 12 Warnings | **0 Warnings** | `build/reports/stage7_drc_report.rpt` (Checks found: 0) |
| **Worst Negative Slack (WNS)** | $+0.255\text{ ns}$ | **$+0.114\text{ ns}$** | `build/reports/stage7_timing_summary.rpt` (MET, 0 failing) |
| **Worst Hold Slack (WHS)** | $+0.035\text{ ns}$ | **$+0.051\text{ ns}$** | `build/reports/stage7_timing_summary.rpt` (MET, 0 failing) |
| **Tổng số Endpoints định thời** | 3,026 endpoints | **3,025 endpoints** | Phản ánh chính xác netlist định tuyến thực tế |
| **Slice LUTs sử dụng** | 1,297 (6.24%) | **1,288 (6.19%)** | `build/reports/stage7_utilization.rpt` (1,238 Logic, 50 Memory) |
| **Slice Registers (Flip-Flops)** | 878 (2.11%) | **881 (2.12%)** | Tăng đúng 3 FFs (2FF đồng bộ reset BRAM + 1FF UART handshake) |
| **Block RAM Tiles** | 5.5 (11.00%) | **5.5 (11.00%)** | 4 RAMB36E1 (RAM 16 KiB) + 1 RAMB36E1 (OBUF) + 1 RAMB18E1 (IBUF) |
| **DSP48E1 Multipliers** | 0 (0.00%) | **0 (0.00%)** | Bảo toàn 100% DSP; phép nhân signed tổ hợp hoàn toàn bằng LUTs |
| **Độ trễ tính toán 1 cửa sổ 3×3** | "Khoảng 25 chu kỳ" | **Đúng 30 chu kỳ tính toán** | `tb_conv_window_reader.sv` console: `wait_cycles = 30` |
| **Độ phủ Hồi quy Hệ thống** | 7/7 testcases SoC | **8/8 testcases SoC + 9/9 TBs** | Bổ sung TEST 8 Warm Reboot; full regression 9/9 PASS |
| **Kiểm chứng An toàn Reset BRAM** | Chưa có TB chuyên biệt | **10/10 Scenarios PASS** | `scripts/run_reset_safety_test.py` (tb_soc_ram_2ff_safety.sv) |
| **Kiểm chứng Giải mã Nối tiếp UART** | Chỉ quan sát LED | **57/57 Bytes Giải mã Chuẩn** | `scripts/run_uart_verification.py` (tb_fpga_top_uart.sv, 115200 8N1) |
| **Bo mạch Mục tiêu** | Một số nơi nhắc Arty A7 | **Digilent Basys 3 duy nhất** | `constraints/stage7_board.xdc` (xc7a35tcpg236-1, W5, U18, A18) |

---

## 3. CHI TIẾT CÁC NỘI DUNG HIỆU CHỈNH TRONG BÁO CÁO V14

### 3.1. Phần Mở Đầu & Tóm Tắt Kỹ Thuật (Front Matter)
- Cập nhật số phiên bản sang **V14**.
- Cập nhật số liệu thực thi Vivado tại Mục Tóm tắt kỹ thuật: 1,288 Slice LUTs (6.19%), 881 Slice Registers (2.12%), $WNS = +0.114\text{ ns}$, $WHS = +0.051\text{ ns}$, 0 cảnh báo DRC (triệt tiêu 12 cảnh báo `REQP-1839`).
- Khẳng định duy nhất kit thực nghiệm là **Digilent Basys 3**.

### 3.2. Chương 2: Cơ Sở Lý Thuyết & Vi Kiến Trúc Đồ Họa
- **Hình 2.1 (Sơ đồ kiến trúc tổng quan SoC):** Thay thế hình ảnh mới, chuẩn hóa khối bộ nhớ thành `Unified RAM (soc_ram) 16 KiB` với bộ đồng bộ 2FF `ASYNC_REG`, giải mã địa chỉ `0x0000_0000` (RAM), `0x1000_0000` (MMIO), `0x2000_0000` (Debug), và cơ chế Anti-Deadlock $\ge \text{0x3000\_0000}$.
- **Hình 2.2 (Giản đồ thời gian PicoRV32 Native Memory Interface):** Chuẩn hóa địa chỉ minh họa sang `0x1000_0004` (đọc thanh ghi `REG_ACCEL_STATUS`) và `0x1000_0000` (ghi thanh ghi `REG_ACCEL_CTRL` phát xung `START`).
- **Hình 2.4 (Datapath khối MAC signed INT8) & Hình 2.6 (FSM khối dot9_int8):** Giữ nguyên độ sắc nét cao và chuẩn hóa mô tả khớp 100% với RTL `mac_int8.sv` và `dot9_int8.sv`. Khẳng định `int8_multiplier` là phép nhân tổ hợp bù hai signed INT8 dùng toán tử `*` (LUT-based combinational multiplier), không nhầm lẫn với kiến trúc bit-serial MBS.

### 3.3. Chương 3: Thiết Kế & Hiện Thực Vi Kiến Trúc RTL
- **Mục 3.11 (soc_ram.sv):** Bổ sung phân tích chuyên sâu về bộ đồng bộ 2 tầng Flip-Flop nội bộ (`rst_sync_local_0`, `rst_sync_local_1`) mang thuộc tính chỉ dẫn tổng hợp `(* ASYNC_REG = "TRUE" *)`. Giải thích cơ chế cách ly reset bất đồng bộ để đáp ứng khuyến cáo của AMD/Xilinx và triệt tiêu 12 cảnh báo `REQP-1839`.
- **Mục 3.13 (soc_top.sv):** Cập nhật cơ chế Anti-Deadlock, ghi nhận việc kiểm chứng tiêm lỗi bus chủ động ở cả cấp MMIO (`0xDEADBEEF`) và cấp SoC (`0xDEAD_DEAD`, `invalid_ready`).
- **Mục 3.15 (fpga_top.sv):** 
  - Mô tả mạch đồng bộ reset 2 lớp: Tầng board-level AASD kết hợp tầng 2FF ASYNC_REG nội bộ của `soc_ram`.
  - Mô tả FSM UART Transmitter mới: phát `BOOT: SoC OK` ngay sau xả reset, bắt tay 2 nhịp tin cậy, xuất 4 khối thông điệp (57 bytes ASCII).

### 3.4. Chương 4: Testbench & Mô Phỏng Kiểm Chứng RTL
- **Khối conv_window_reader (Mục 4.5):** Xác định chính xác độ trễ thực tế: **đúng 30 chu kỳ tính toán** (wait_cycles = 30) cho mỗi cửa sổ trượt $3 \times 3$, căn cứ trực tiếp theo waveform và log console `tb_conv_window_reader.sv`.
- **Nâng cấp độ phủ kiểm chứng F-03 (Mục 4.7):** Bổ sung mô tả bài test **TEST 10** trong `tb_conv_accelerator_top.sv` với ma trận signed INT8 $[-128, +127]$ phi tuyến, kernel bất đối xứng, đối chiếu 900/900 phần tử với Golden Reference độc lập và các điểm kiểm tra biên cứng (Head, Mid, Tail).
- **Phân biệt kiểm thử Reset (Mục 4.9):** Phân định rạch ròi giữa:
  - **TEST 8 trong `tb_soc_top.sv`:** Kiểm tra **Warm Reboot / Post-execution Reset Recovery** sau khi CPU hoàn thành Run 1 và Run 2 (khi CPU đang ở vòng lặp nhàn rỗi idle).
  - **10 kịch bản trong `tb_soc_ram_2ff_safety.sv`:** Kiểm tra **Mid-Transaction Reset Injection** trực tiếp khi BRAM đang có giao dịch ghi dở dang (pre-edge, post-edge, partial byte write, sustained reset, bus noise).
- **Giải mã UART (Mục 4.10):** Ghi nhận kết quả testbench `tb_fpga_top_uart.sv` giải mã luồng bit thực tế 115200 8N1 thu nhận trọn vẹn 57/57 bytes.

### 3.5. Chương 5: Kết Quả Thực Nghiệm & Đánh Giá Hiệu Năng
- **Bảng 5.1 & Mục 5.3 (Resource Utilization):** Cập nhật chính xác số liệu sau Phase 3G: 1,288 Slice LUTs (6.19%), 881 Slice Registers (2.12%), 5.5 BRAM tiles (11.00%), 0 DSPs (0.00%).
- **Hình 5.2:** Thay thế hình ảnh báo cáo trích xuất Slice Logic với số liệu mới 1,288 LUTs và 881 FFs.
- **Bảng 13 (Testbench Summary):** Cập nhật số lượng testcase: Scanner (10 tests), Top Accel (12 tests), MMIO (8 tests), SoC Top (8 tests), ghi nhận thêm 2 bộ kiểm thử chuyên biệt (Reset Safety 10/10 PASS, UART 57/57 bytes PASS).
- **Mục 5.5 & Hình 5.3 (STA Timing Analysis):** Cập nhật $WNS = +0.114\text{ ns}$, $WHS = +0.051\text{ ns}$, $WPWS = +3.750\text{ ns}$, 0/3,025 endpoints vi phạm.
- **Mục 5.6 & Hình 5.4 (DRC Report):** Thay thế hình ảnh báo cáo DRC sạch hoàn toàn: Checks found: 0 (0 Error, 0 Critical Warning, 0 Warning).
- **Bảng 5.2 (So sánh qua các Stage):** Cập nhật hàng Stage 7: LUTs = 1,288, FFs = 881, WNS = +0.114 ns, Trạng thái: PASS TO BITSTREAM (0 DRC Warnings).
- **Mục 5.10 (Phân định tầng độ trễ):** Chuẩn hóa độ trễ 1 cửa sổ $3 \times 3$ thành 30 chu kỳ; toàn bộ 900 cửa sổ tiêu tốn 27,000 chu kỳ tính toán thuần túy.

### 3.6. Chương 6: Kết Luận & Đối Chiếu Các Hạn Chế F-04 Đến F-09
- **Mục 6.1 (Tổng kết kết quả đạt được):** Đồng bộ các chỉ số nghiệm thu: 1,288 LUTs, 881 FFs, 5.5 BRAMs, 0 DSPs, WNS = +0.114 ns, WHS = +0.051 ns, 0 DRC Warnings, 9/9 regression tests PASS.
- **Mục 6.3 (Những mặt hạn chế của đề tài):** Cấu trúc lại theo đúng 6 finding kỹ thuật gốc từ đợt audit của Gemini Argon High:
  1. **F-04 (Address Decoding & Aliasing):** Phân tích tính tối giản của bộ giải mã 4 bit cao, cơ chế anti-deadlock bảo vệ bus.
  2. **F-05 (Documentation Alignment):** Chuẩn hóa tính nhất quán tài liệu, khẳng định duy nhất kit Basys 3.
  3. **F-06 (Advanced DV Metrics):** Đánh giá khoảng trống giữa Directed Tests (đã hoàn thành 100%) và môi trường UVM / Coverage Metrics (định hướng Capstone).
  4. **F-07 (Window Sequencer FSM Throughput):** Phân tích kiến trúc FSM tuần tự 30 chu kỳ/cửa sổ so với kiến trúc Line Buffer streaming.
  5. **F-08 (MMIO Polling Overhead):** Đánh giá chi phí chu kỳ khi CPU trung chuyển dữ liệu gián tiếp qua MMIO so với cơ chế DMA Bus Master.
  6. **F-09 (Buffer Bounds & Clamping):** Nhận định về việc khống chế vòng lặp trong phần mềm so với việc tích hợp khối kẹp biên phần cứng (Address Clamping).
- **Mục 6.4 - 6.7 (Hướng phát triển):** Giữ nguyên định hướng thận trọng: Trạng thái nghiệm thu là **PASS TO BITSTREAM — Hardware Test Pending** (chưa tuyên bố đo đạc phần cứng thực tế khi chưa cắm kit vật lý trong lab).

---

## 4. TÌNH TRẠNG LƯU TRỮ VÀ TOÀN VẸN TỆP TIN

Các tệp tin kết quả chính thức đã được biên dịch, đối soát và lưu trữ đồng bộ tại hai vị trí:
1. **Thư mục làm việc dự án:** `D:\DA2\SoC RISCV\`
   - `Bao_Cao_Do_An_2_V14.docx` (Dung lượng: ~5.4 MB, mở được hoàn hảo trên Word 2016/365).
   - `Bao_Cao_Do_An_2_V14.pdf` (Dung lượng: ~3.3 MB, đúng 87 trang, không bị lỗi phân trang).
   - `V13_TO_V14_CHANGELOG.md` (Bản nhật ký thay đổi kỹ thuật này).
2. **Thư mục gốc lưu trữ:** `D:\DA2\`
   - `Bao_Cao_Do_An_2_V14.docx`
   - `Bao_Cao_Do_An_2_V14.pdf`
   - `V13_TO_V14_CHANGELOG.md`
   - Bản sao lưu nguyên vẹn: `D:\DA2\Backup_V13\Bao_Cao_Do_An_2_V13.docx` và `Bao_Cao_Do_An_2_V13.pdf`.

---

## 5. KẾT LUẬN NGHIỆM THU PHIÊN BẢN V14

Phiên bản **Báo Cáo Đồ Án 2 V14** đáp ứng trọn vẹn 100% các yêu cầu nghiệm thu kỹ thuật:
- Tính trung thực học thuật tuyệt đối: Toàn bộ số liệu DRC, STA, tài nguyên và kiểm chứng đều trích xuất trực tiếp từ các báo cáo build và log mô phỏng thực tế.
- Hình ảnh sắc nét, đúng nguồn: Các sơ đồ kiến trúc và báo cáo Vivado đã được thay thế bằng hình ảnh cập nhật mới nhất, không sử dụng hình ảnh giả lập.
- Giữ vững phạm vi Đồ án 2: Không phóng đại tính năng, không nhận nhầm vi kiến trúc, phân định rạch ròi giữa thành quả hoàn thành và các nghiên cứu mở rộng trong tương lai.
