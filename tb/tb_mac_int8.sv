// ============================================================================
// Testbench Name: tb_mac_int8
// Description:    Comprehensive Self-Checking Testbench for mac_int8
// Target:         Stage 1 Verification - RISC-V INT8 Convolution Accelerator
// ============================================================================

`timescale 1ns / 1ps

module tb_mac_int8;

    // Tín hiệu điều khiển và dữ liệu cho DUT
    logic               clk;
    logic               rst;
    logic               clear;
    logic               valid;
    logic signed [7:0]  tb_x;
    logic signed [7:0]  tb_w;
    logic signed [31:0] dut_acc;

    // Biến mô hình tham chiếu (Golden Reference) và thống kê
    int golden_acc   = 0;
    int total_checks = 0;
    int pass_count   = 0;
    int fail_count   = 0;

    // Khởi tạo DUT
    mac_int8 dut (
        .clk   (clk),
        .rst   (rst),
        .clear (clear),
        .valid (valid),
        .x     (tb_x),
        .w     (tb_w),
        .acc   (dut_acc)
    );

    // ------------------------------------------------------------------------
    // Clock Generation: Chu kỳ 10ns (Tần số 100MHz)
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // Watchdog Timer chống treo mô phỏng
    // ------------------------------------------------------------------------
    initial begin
        #50ms;
        $display("[FATAL WATCHDOG] Simulation exceeded time limit of 50ms!");
        $finish(1);
    end

    // ------------------------------------------------------------------------
    // Task: apply_and_check
    // Nguyên tắc đồng bộ và chống race condition:
    // - Lái stimulus (rst, clear, valid, x, w) tại @(negedge clk)
    // - Cho phép thời gian ổn định trước sườn dương (setup = 5ns, hold = 5ns)
    // - Đợi sườn dương @(posedge clk); #1; để DUT hoàn tất cập nhật nonblocking
    // - Kiểm tra dut_acc với golden_acc
    // ------------------------------------------------------------------------
    task apply_and_check(
        input logic              in_rst,
        input logic              in_clear,
        input logic              in_valid,
        input logic signed [7:0] in_x,
        input logic signed [7:0] in_w,
        input string             test_context
    );
        int term;

        // Bước 1: Lái tín hiệu ở sườn âm clk
        @(negedge clk);
        rst   = in_rst;
        clear = in_clear;
        valid = in_valid;
        tb_x  = in_x;
        tb_w  = in_w;

        // Bước 2: Cập nhật Golden Reference Model cho chu kỳ clock tiếp theo
        // Thứ tự ưu tiên phần cứng: rst > clear > valid
        if (in_rst) begin
            golden_acc = 0;
        end else if (in_clear) begin
            // Nếu cả clear và valid cùng bằng 1: ưu tiên clear, không nhận tích
            golden_acc = 0;
        end else if (in_valid) begin
            // Tích hợp signed 8-bit * signed 8-bit và cộng dồn vào 32-bit
            term = int'(in_x) * int'(in_w);
            golden_acc = golden_acc + term;
        end
        // Nếu in_valid == 0: golden_acc giữ nguyên giá trị

        // Bước 3: Đợi sườn dương và một khoảng trễ nhỏ để DUT hoàn tất cập nhật
        @(posedge clk);
        #1;

        total_checks++;

        // Bước 4: So sánh DUT output với Golden Reference
        if (dut_acc === 32'(golden_acc)) begin
            pass_count++;
        end else begin
            fail_count++;
            $display("[FAIL MISMATCH @ %0t ps] %s", $time, test_context);
            $display("  Inputs: rst=%b, clear=%b, valid=%b, x=%0d (8'h%0h), w=%0d (8'h%0h)",
                     in_rst, in_clear, in_valid, in_x, in_x, in_w, in_w);
            $display("  Expected ACC: %0d (32'h%08h) | Actual DUT ACC: %0d (32'h%08h)",
                     golden_acc, golden_acc, dut_acc, dut_acc);
            if (fail_count >= 10) begin
                $display("[FATAL] Excessive failures. Aborting testbench.");
                $finish(1);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Kịch bản kiểm tra chi tiết
    // ------------------------------------------------------------------------
    initial begin
        // Khởi tạo ghi nhận waveform
        $dumpfile("mac_int8_waveform.vcd");
        $dumpvars(0, tb_mac_int8);

        $display("==================================================================");
        $display("   TESTBENCH: mac_int8 Comprehensive Verification");
        $display("==================================================================");

        // Khởi tạo các tín hiệu
        rst   = 1'b1;
        clear = 1'b0;
        valid = 1'b0;
        tb_x  = 8'sd0;
        tb_w  = 8'sd0;
        golden_acc = 0;

        // Giữ reset trong 3 chu kỳ ban đầu
        repeat (3) @(posedge clk);

        // ====================================================================
        // PHASE 1: Synchronous Reset Verification
        // ====================================================================
        $display("\n[Phase 1] Testing Synchronous Reset...");
        apply_and_check(1'b1, 1'b0, 1'b0, 8'sd0, 8'sd0, "Reset active, idle inputs");
        apply_and_check(1'b1, 1'b0, 1'b1, 8'sd50, 8'sd10, "Reset active while valid=1 (must ignore data)");
        apply_and_check(1'b0, 1'b0, 1'b0, 8'sd0, 8'sd0, "Deassert reset, idle cycle");

        // ====================================================================
        // PHASE 2: Synchronous Clear Verification
        // ====================================================================
        $display("[Phase 2] Testing Synchronous Clear...");
        // Tích lũy 1 giá trị: 10 * 10 = 100
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd10, 8'sd10, "Accumulate 10*10 = 100");
        // Clear về 0
        apply_and_check(1'b0, 1'b1, 1'b0, 8'sd0, 8'sd0, "Assert clear, acc must reset to 0");
        // Idle
        apply_and_check(1'b0, 1'b0, 1'b0, 8'sd0, 8'sd0, "Idle after clear, acc remains 0");

        // ====================================================================
        // PHASE 3: Simultaneous Clear and Valid (Clear priority check)
        // ====================================================================
        $display("[Phase 3] Testing Simultaneous Clear and Valid (Clear Priority)...");
        // Tích lũy giá trị: 7 * 8 = 56
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd7, 8'sd8, "Accumulate 7*8 = 56");
        // Kích hoạt đồng thời clear = 1 VÀ valid = 1 với x=20, w=5:
        // Yêu cầu: acc phải về 0, KHÔNG được nhận 20*5 = 100.
        apply_and_check(1'b0, 1'b1, 1'b1, 8'sd20, 8'sd5, "Simultaneous clear=1 & valid=1: must clear to 0, discard data");
        // Sau đó tiếp tục tích lũy giá trị mới: 3 * 4 = 12
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd3, 8'sd4, "Accumulate 3*4 = 12 after clear");

        // Xóa sạch để vào phase tiếp theo
        apply_and_check(1'b0, 1'b1, 1'b0, 8'sd0, 8'sd0, "Clear for Phase 4");

        // ====================================================================
        // PHASE 4: Basic Arithmetic Sign Combinations & Zero Operands
        // ====================================================================
        $display("[Phase 4] Testing Arithmetic Sign Combinations & Zero Operands...");
        // (+) * (+) : 15 * 6 = 90 -> acc = 90
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd15, 8'sd6, "(+) * (+): 15 * 6");
        // (+) * (-) : 12 * (-5) = -60 -> acc = 30
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd12, -8'sd5, "(+) * (-): 12 * -5");
        // (-) * (+) : (-8) * 10 = -80 -> acc = -50
        apply_and_check(1'b0, 1'b0, 1'b1, -8'sd8, 8'sd10, "(-) * (+): -8 * 10");
        // (-) * (-) : (-7) * (-9) = 63 -> acc = 13
        apply_and_check(1'b0, 1'b0, 1'b1, -8'sd7, -8'sd9, "(-) * (-): -7 * -9");
        // Operands with Zero
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd0, 8'sd127, "Zero x: 0 * 127");
        apply_and_check(1'b0, 1'b0, 1'b1, -8'sd128, 8'sd0, "Zero w: -128 * 0");
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd0, 8'sd0, "Both zero: 0 * 0");

        // Clear cho phase tiếp theo
        apply_and_check(1'b0, 1'b1, 1'b0, 8'sd0, 8'sd0, "Clear for Phase 5");

        // ====================================================================
        // PHASE 5: Extreme Boundary Values (-128 and +127)
        // ====================================================================
        $display("[Phase 5] Testing Extreme Boundary Values (-128, 127)...");
        // (-128) * (-128) = +16384 (0x4000)
        apply_and_check(1'b0, 1'b0, 1'b1, -8'sd128, -8'sd128, "Extreme: -128 * -128 = +16384");
        // (-128) * (+127) = -16256 -> acc = 16384 - 16256 = 128
        apply_and_check(1'b0, 1'b0, 1'b1, -8'sd128, 8'sd127, "Extreme: -128 * 127 = -16256");
        // (+127) * (-128) = -16256 -> acc = 128 - 16256 = -16128
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd127, -8'sd128, "Extreme: 127 * -128 = -16256");
        // (+127) * (+127) = +16129 -> acc = -16128 + 16129 = 1
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd127, 8'sd127, "Extreme: 127 * 127 = +16129");
        // (-1) * (-128) = +128 -> acc = 1 + 128 = 129
        apply_and_check(1'b0, 1'b0, 1'b1, -8'sd1, -8'sd128, "Extreme: -1 * -128 = +128");

        // Clear cho phase tiếp theo
        apply_and_check(1'b0, 1'b1, 1'b0, 8'sd0, 8'sd0, "Clear for Phase 6");

        // ====================================================================
        // PHASE 6: Valid Gaps and Bubbles (Accumulator Hold State Check)
        // ====================================================================
        $display("[Phase 6] Testing Valid Gaps/Bubbles (Acc Hold Check)...");
        // Tích lũy 1: 5 * 6 = 30
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd5, 8'sd6, "Accumulate 5*6 = 30");
        // valid = 0 trong 3 chu kỳ liên tiếp, dù x, w thay đổi, acc PHẢI giữ nguyên 30
        apply_and_check(1'b0, 1'b0, 1'b0, 8'sd99, 8'sd99, "Bubble 1: valid=0, acc must hold 30");
        apply_and_check(1'b0, 1'b0, 1'b0, -8'sd50, 8'sd10, "Bubble 2: valid=0, acc must hold 30");
        apply_and_check(1'b0, 1'b0, 1'b0, 8'sd123, -8'sd12, "Bubble 3: valid=0, acc must hold 30");
        // Tiếp tục valid = 1: cộng thêm 4 * 5 = 20 -> acc = 50
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd4, 8'sd5, "Resume valid=1: 4*5 = 20, acc becomes 50");
        // Bubble 1 chu kỳ
        apply_and_check(1'b0, 1'b0, 1'b0, 8'sd0, 8'sd0, "Bubble 4: valid=0, acc must hold 50");
        // Tích lũy tiếp: (-10) * 5 = -50 -> acc = 0
        apply_and_check(1'b0, 1'b0, 1'b1, -8'sd10, 8'sd5, "Accumulate -10*5 = -50, acc becomes 0");

        // ====================================================================
        // PHASE 7: Reset Mid-Accumulation
        // ====================================================================
        $display("[Phase 7] Testing Mid-Accumulation Reset...");
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd25, 8'sd4, "Accumulate 25*4 = 100");
        apply_and_check(1'b0, 1'b0, 1'b1, 8'sd10, 8'sd10, "Accumulate 10*10 = 100 (acc=200)");
        // Đột ngột rst = 1
        apply_and_check(1'b1, 1'b0, 1'b1, 8'sd10, 8'sd10, "Assert rst=1 mid-accumulation, acc must reset to 0");
        apply_and_check(1'b0, 1'b0, 1'b0, 8'sd0, 8'sd0, "Deassert rst, acc remains 0");

        // ====================================================================
        // PHASE 8: 9-Pair CNN Kernel Sequence
        // Yêu cầu đặc tả: 9 cặp x = -128, w = -128 -> tổng mong đợi = 147,456
        // ====================================================================
        $display("[Phase 8] Testing 9-Pair CNN Kernel Sequence (All -128 * -128)...");
        apply_and_check(1'b0, 1'b1, 1'b0, 8'sd0, 8'sd0, "Clear acc before CNN kernel");

        for (int k = 1; k <= 9; k++) begin
            apply_and_check(1'b0, 1'b0, 1'b1, -8'sd128, -8'sd128,
                            $sformatf("CNN Kernel Pair %0d/9: (-128)*(-128)", k));
        end

        // Kiểm tra chắc chắn tổng cuối đúng 147456
        if (dut_acc === 32'd147456) begin
            $display(">>> CNN 9-Pair All-(-128) sequence verified: ACC = 147,456 (MATCH!)");
        end else begin
            $fatal(1, ">>> CNN 9-Pair FAILED! Expected 147456, Actual: %0d", dut_acc);
        end

        // Kiểm tra thêm một kernel 3x3 thực tế (Sobel horizontal filter [-1 0 1; -2 0 2; -1 0 1])
        $display("[Phase 8.1] Testing Realistic 3x3 Filter Convolution...");
        apply_and_check(1'b0, 1'b1, 1'b0, 8'sd0, 8'sd0, "Clear acc before Sobel");
        begin : blk_sobel
            logic signed [7:0] pixels[9];
            logic signed [7:0] kernel[9];
            pixels = '{-8'sd10, 8'sd20, 8'sd30, -8'sd40, 8'sd50, 8'sd60, -8'sd70, 8'sd80, 8'sd90};
            kernel = '{-8'sd1,  8'sd0,  8'sd1,  -8'sd2,  8'sd0,  8'sd2,  -8'sd1,  8'sd0,  8'sd1};
            for (int k = 0; k < 9; k++) begin
                apply_and_check(1'b0, 1'b0, 1'b1, pixels[k], kernel[k],
                                $sformatf("Sobel Step %0d: pixel=%0d, kernel=%0d", k, pixels[k], kernel[k]));
            end
        end

        // ====================================================================
        // PHASE 9: Randomized Deterministic Regression Testing
        // - Seed cố định: 32'h2026_1003 (đảm bảo tính tái lập 100%)
        // - 120 chuỗi ngẫu nhiên (yêu cầu tối thiểu 100)
        // - Chiều dài mỗi chuỗi từ 1 đến 64 cặp
        // - Chèn khoảng nghỉ valid=0 ngẫu nhiên (mô phỏng trễ bộ nhớ/bus)
        // - Kiểm tra accumulator sau TỪNG chu kỳ (cả khi valid=1 và valid=0)
        // ====================================================================
        $display("\n[Phase 9] Running 120 Randomized Sequences with Fixed Seed 32'h20261003...");
        begin : blk_random_regression
            int seed;
            int seq;
            int seq_len;
            int pairs_sent;
            int roll;
            logic signed [7:0] rand_x;
            logic signed [7:0] rand_w;
            logic signed [7:0] dummy_x;
            logic signed [7:0] dummy_w;

            seed = 32'h2026_1003;

            for (seq = 1; seq <= 120; seq++) begin
                // Xóa accumulator trước mỗi chuỗi mới
                apply_and_check(1'b0, 1'b1, 1'b0, 8'sd0, 8'sd0, $sformatf("Seq #%0d Init Clear", seq));

                // Chiều dài chuỗi ngẫu nhiên từ 1 đến 64 cặp dữ liệu
                seq_len = 1 + (($random(seed) & 32'h7FFFFFFF) % 64);
                pairs_sent = 0;

                while (pairs_sent < seq_len) begin
                    // Xác suất 70% gửi cặp dữ liệu (valid=1), 30% chèn khoảng nghỉ (valid=0)
                    roll = ($random(seed) & 32'h7FFFFFFF) % 100;
                    if (roll < 70) begin
                        // Sinh toán hạng INT8 ngẫu nhiên trong dải [-128, 127]
                        rand_x = 8'($random(seed));
                        rand_w = 8'($random(seed));
                        pairs_sent++;
                        apply_and_check(1'b0, 1'b0, 1'b1, rand_x, rand_w,
                                        $sformatf("Seq #%0d Pair %0d/%0d (x=%0d, w=%0d)", seq, pairs_sent, seq_len, rand_x, rand_w));
                    end else begin
                        // Chu kỳ stall / bubble: valid = 0
                        dummy_x = 8'($random(seed));
                        dummy_w = 8'($random(seed));
                        apply_and_check(1'b0, 1'b0, 1'b0, dummy_x, dummy_w,
                                        $sformatf("Seq #%0d Stall Bubble", seq));
                    end
                end

                // Kết thúc mỗi chuỗi bằng 2 chu kỳ idle để kiểm tra giá trị giữ nguyên
                apply_and_check(1'b0, 1'b0, 1'b0, 8'sd0, 8'sd0, $sformatf("Seq #%0d Post-Idle 1", seq));
                apply_and_check(1'b0, 1'b0, 1'b0, 8'sd0, 8'sd0, $sformatf("Seq #%0d Post-Idle 2", seq));
            end
        end

        // ====================================================================
        // TỔNG KẾT KẾT QUẢ KIỂM TRA
        // ====================================================================
        $display("\n==================================================================");
        $display("   MAC_INT8 VERIFICATION SUMMARY");
        $display("==================================================================");
        $display("  Total Cycle Checks Performed : %0d", total_checks);
        $display("  Total Passed Checks          : %0d", pass_count);
        $display("  Total Failed Checks          : %0d", fail_count);
        $display("==================================================================");

        if (fail_count == 0 && total_checks > 1000) begin
            $display(">>> TEST PASSED: mac_int8 COMPLETELY VERIFIED WITH ZERO ERRORS! <<<");
            $finish(0);
        end else begin
            $fatal(1, ">>> TEST FAILED: Completed with %0d errors! <<<", fail_count);
        end
    end

endmodule
