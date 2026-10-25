// ============================================================================
// Testbench Name: tb_int8_multiplier
// Description:    Exhaustive Self-Checking Testbench for int8_multiplier
//                 Tests all 256 x 256 = 65,536 combinations of signed INT8.
// ============================================================================

`timescale 1ns / 1ps

module tb_int8_multiplier;

    // Tín hiệu giao tiếp với DUT
    logic signed [7:0]  tb_x;
    logic signed [7:0]  tb_w;
    logic signed [15:0] dut_product;

    // Biến thống kê kiểm tra
    int total_tests = 0;
    int pass_count  = 0;
    int fail_count  = 0;

    // Khởi tạo DUT
    int8_multiplier dut (
        .x       (tb_x),
        .w       (tb_w),
        .product (dut_product)
    );

    // Watchdog Timer chống treo testbench
    initial begin
        #100ms;
        $display("[WATCHDOG TIMEOUT] Testbench run exceeded maximum allowable time!");
        $finish(1);
    end

    // Quá trình kiểm tra exhaustive (toàn diện 100%)
    initial begin
        int expected_val;
        int actual_val;

        // Khởi tạo xuất waveform
        $dumpfile("int8_multiplier_waveform.vcd");
        $dumpvars(0, tb_int8_multiplier);

        $display("==================================================================");
        $display("   TESTBENCH: int8_multiplier (Exhaustive 65,536 Cases Verification)");
        $display("==================================================================");

        tb_x = 8'sd0;
        tb_w = 8'sd0;
        #10;

        // Vòng lặp quét toàn bộ dải biểu diễn của signed 8-bit (-128 đến +127)
        for (int i = -128; i <= 127; i++) begin
            for (int j = -128; j <= 127; j++) begin
                tb_x = 8'(i);
                tb_w = 8'(j);

                #1; // Đợi lan truyền qua mạch tổ hợp

                // Mô hình tham chiếu (Golden Reference) tính bằng kiểu 32-bit int
                expected_val = i * j;
                actual_val   = int'(dut_product);

                total_tests++;

                if (actual_val === expected_val) begin
                    pass_count++;
                end else begin
                    fail_count++;
                    $display("[ERROR MISMATCH] Case #%0d: x = %0d (8'h%0h), w = %0d (8'h%0h) | Expected = %0d (16'h%0h), Actual = %0d (16'h%0h)",
                             total_tests, i, tb_x, j, tb_w, expected_val, 16'(expected_val), actual_val, dut_product);
                    // Dừng ngay nếu phát hiện lỗi đầu tiên để kiểm tra
                    if (fail_count >= 10) begin
                        $display("[ABORT] Too many errors encountered (>= 10). Aborting testbench.");
                        $finish(1);
                    end
                end
            end
        end

        // Báo cáo tổng kết
        $display("------------------------------------------------------------------");
        $display("VERIFICATION SUMMARY:");
        $display("  Total Vectors Tested : %0d / 65536", total_tests);
        $display("  Passed Vectors       : %0d", pass_count);
        $display("  Failed Vectors       : %0d", fail_count);
        $display("------------------------------------------------------------------");

        if (fail_count == 0 && total_tests == 65536) begin
            $display(">>> TEST PASSED: ALL 65,536 SIGNED INT8 COMBINATIONS MATCH GOLDEN REFERENCE! <<<");
            $finish(0);
        end else begin
            $fatal(1, ">>> TEST FAILED: Verification completed with %0d mismatches! <<<", fail_count);
        end
    end

endmodule
