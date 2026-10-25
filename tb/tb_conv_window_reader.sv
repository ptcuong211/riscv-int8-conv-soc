// ============================================================================
// Module Name: tb_conv_window_reader
// Description: Comprehensive Self-Checking Testbench for conv_window_reader
// Target:      RISC-V INT8 Convolution Accelerator (Stage 3)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module tb_conv_window_reader;

    // ------------------------------------------------------------------------
    // Tin hieu ket noi DUT
    // ------------------------------------------------------------------------
    logic                    clk;
    logic                    rst;

    // Cong ghi Input Buffer
    logic                    ibuf_wr_en;
    logic [9:0]              ibuf_wr_addr;
    logic signed [7:0]       ibuf_wr_data;

    // Cong ghi Weight Buffer
    logic                    wbuf_wr_en;
    logic [3:0]              wbuf_wr_addr;
    logic signed [7:0]       wbuf_wr_data;

    // Giao tiep dieu khien
    logic                    start_window;
    logic [4:0]              out_row;
    logic [4:0]              out_col;

    // Dau ra
    logic                    busy;
    logic                    window_done;
    logic signed [31:0]      window_result;

    // Tin hieu quan sat (Monitoring)
    logic [3:0]              mon_pair_idx;
    logic signed [7:0]       mon_x;
    logic signed [7:0]       mon_w;
    logic                    mon_valid;
    logic                    mon_ready;

    // ------------------------------------------------------------------------
    // Ma tran bo nho tham chieu (Golden Model trong Testbench)
    // ------------------------------------------------------------------------
    logic signed [7:0] golden_image[0:31][0:31];
    logic signed [7:0] golden_kernel[0:8];

    // Thong ke kiem chung
    int total_windows_tested = 0;
    int total_windows_passed = 0;
    int total_windows_failed = 0;
    int total_pair_checks    = 0;

    // ------------------------------------------------------------------------
    // Tao xung clock 100 MHz (chu ky 10ns)
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Khoi tao DUT
    // ------------------------------------------------------------------------
    conv_window_reader #(
        .IMG_WIDTH   (32),
        .IMG_HEIGHT  (32),
        .KERNEL_SIZE (3)
    ) u_dut (
        .clk           (clk),
        .rst           (rst),
        .ibuf_wr_en    (ibuf_wr_en),
        .ibuf_wr_addr  (ibuf_wr_addr),
        .ibuf_wr_data  (ibuf_wr_data),
        .wbuf_wr_en    (wbuf_wr_en),
        .wbuf_wr_addr  (wbuf_wr_addr),
        .wbuf_wr_data  (wbuf_wr_data),
        .start_window  (start_window),
        .out_row       (out_row),
        .out_col       (out_col),
        .busy          (busy),
        .window_done   (window_done),
        .window_result (window_result),
        .mon_pair_idx  (mon_pair_idx),
        .mon_x         (mon_x),
        .mon_w         (mon_w),
        .mon_valid     (mon_valid),
        .mon_ready     (mon_ready)
    );

    // ------------------------------------------------------------------------
    // Ghi waveform VCD
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("conv_window_reader_waveform.vcd");
        $dumpvars(0, tb_conv_window_reader);
    end

    // ------------------------------------------------------------------------
    // Watchdog Timeout (1 ms)
    // ------------------------------------------------------------------------
    initial begin
        #1000000;
        $display("\n[FATAL TIMEOUT] Mo phong bi treo vuot qua 1,000,000 ns!");
        $fatal(1);
    end

    // ------------------------------------------------------------------------
    // Task: Nap anh 32x32 va 9 trong so vao RAM
    // ------------------------------------------------------------------------
    task automatic load_buffers();
        int addr;
        $display("\n>>> [1] Dang nap du lieu vao Input Buffer (32x32) va Weight Buffer (9)...");
        
        // 1. Nap Weight Buffer
        for (int k = 0; k < 9; k++) begin
            @(negedge clk);
            wbuf_wr_en   <= 1'b1;
            wbuf_wr_addr <= k[3:0];
            wbuf_wr_data <= golden_kernel[k];
        end
        @(negedge clk);
        wbuf_wr_en <= 1'b0;

        // 2. Nap Input Buffer
        for (int r = 0; r < 32; r++) begin
            for (int c = 0; c < 32; c++) begin
                addr = (r << 5) | c;
                @(negedge clk);
                ibuf_wr_en   <= 1'b1;
                ibuf_wr_addr <= addr[9:0];
                ibuf_wr_data <= golden_image[r][c];
            end
        end
        @(negedge clk);
        ibuf_wr_en <= 1'b0;

        $display("    -> Da nap xong 1024 pixel vao Input Buffer va 9 trong so vao Weight Buffer.");
    endtask

    // ------------------------------------------------------------------------
    // Task: Kiem tra mot cua so tai toa do (r, c)
    // ------------------------------------------------------------------------
    task automatic test_single_window(
        input string      test_name,
        input logic [4:0] target_row,
        input logic [4:0] target_col
    );
        logic signed [63:0] expected_sum;
        logic signed [7:0]  expected_pixels[9];
        logic signed [7:0]  expected_weights[9];
        int                 accepted_pairs;
        int                 wait_cycles;
        logic signed [31:0] result_at_done;

        // 1. Tinh toan Golden Model cho cua so nay
        expected_sum   = 64'sd0;
        accepted_pairs = 0;
        for (int dr = 0; dr < 3; dr++) begin
            for (int dc = 0; dc < 3; dc++) begin
                int k = dr * 3 + dc;
                expected_pixels[k]  = golden_image[target_row + dr][target_col + dc];
                expected_weights[k] = golden_kernel[k];
                expected_sum        = expected_sum + (64'(expected_pixels[k]) * 64'(expected_weights[k]));
            end
        end

        // 2. Kiem tra DUT dang o trang thai ranh (busy=0)
        @(negedge clk);
        if (busy !== 1'b0 || window_done !== 1'b0) begin
            $display("[FAIL] %s: DUT khong o IDLE truoc khi bat dau! busy=%b", test_name, busy);
            $fatal(1);
        end

        // 3. Phat xung start_window trong 1 chu ky
        start_window <= 1'b1;
        out_row      <= target_row;
        out_col      <= target_col;
        @(negedge clk);
        start_window <= 1'b0;

        // 4. Theo doi tung cap toan hang duoc cap vao dot9_int8 qua handshake
        fork
            // Thread A: Monitor va kiem tra tung cap toan hang khi co handshake (accept)
            begin
                while (accepted_pairs < 9) begin
                    @(posedge clk);
                    #1; // Lay mau sau NBA
                    if (mon_valid && mon_ready) begin
                        // Bat tay thanh cong cho cap mon_pair_idx!
                        if (mon_pair_idx !== accepted_pairs[3:0]) begin
                            $display("[FAIL] %s: Sai thu tu cap toan hang! Expected=%0d, Actual=%0d",
                                     test_name, accepted_pairs, mon_pair_idx);
                            $fatal(1);
                        end
                        if (mon_x !== expected_pixels[accepted_pairs]) begin
                            $display("[FAIL] %s: Sai toan hang X tai cap %0d! Expected=%0d, Actual=%0d",
                                     test_name, accepted_pairs, expected_pixels[accepted_pairs], mon_x);
                            $fatal(1);
                        end
                        if (mon_w !== expected_weights[accepted_pairs]) begin
                            $display("[FAIL] %s: Sai toan hang W tai cap %0d! Expected=%0d, Actual=%0d",
                                     test_name, accepted_pairs, expected_weights[accepted_pairs], mon_w);
                            $fatal(1);
                        end
                        accepted_pairs++;
                        total_pair_checks++;
                    end
                end
            end

            // Thread B: Cho xung window_done tu DUT
            begin
                wait_cycles = 0;
                while (!window_done) begin
                    @(posedge clk);
                    #1;
                    wait_cycles++;
                    if (wait_cycles > 50) begin
                        $display("[FAIL] %s: Timeout! DUT khong phat window_done sau 50 chu ky!", test_name);
                        $fatal(1);
                    end
                end
                result_at_done = window_result;

                // Kiem tra gia tri ket qua
                if (result_at_done !== 32'(expected_sum)) begin
                    $display("[FAIL] %s: RESULT MISMATCH tai cua so (%0d, %0d)!",
                             test_name, target_row, target_col);
                    $display("       Expected: %0d (0x%08h)", 32'(expected_sum), 32'(expected_sum));
                    $display("       Actual:   %0d (0x%08h)", result_at_done, result_at_done);
                    $fatal(1);
                end

                // Kiem tra chu ky sau window_done: window_done phai ha ve 0 dung 1 chu ky
                @(posedge clk);
                #1;
                if (window_done !== 1'b0) begin
                    $display("[FAIL] %s: Xung window_done keo dai hon 1 chu ky!", test_name);
                    $fatal(1);
                end
                if (busy !== 1'b0) begin
                    $display("[FAIL] %s: busy khong ha ve 0 sau khi hoan tat cua so!", test_name);
                    $fatal(1);
                end
                // Ket qua phai giu nguyen khi ve IDLE
                if (window_result !== result_at_done) begin
                    $display("[FAIL] %s: window_result bi thay doi khi ve IDLE!", test_name);
                    $fatal(1);
                end
            end
        join

        total_windows_passed++;
        total_windows_tested++;
        $display("[PASS] %s: Cua so (%0d, %0d) -> 9 cap khop 100%%, Expected=%0d, Actual=%0d (Chu ky tinh: %0d)",
                 test_name, target_row, target_col, 32'(expected_sum), result_at_done, wait_cycles);
    endtask

    // ========================================================================
    // MAIN VERIFICATION SEQUENCE
    // ========================================================================
    initial begin
        int seed;
        seed = 32'h20261004;

        $display("==================================================================");
        $display("   TESTBENCH BAT DAU: tb_conv_window_reader (Stage 3 Verification)");
        $display("==================================================================");

        // 1. Khoi tao ma tran anh 32x32 va 9 trong so
        // Kernel Sobel-X phuc vu phat hien bien canh:
        //  [-1,  0,  1]
        //  [-2,  0,  2]
        //  [-1,  0,  1]
        golden_kernel[0] = -8'sd1; golden_kernel[1] =  8'sd0; golden_kernel[2] =  8'sd1;
        golden_kernel[3] = -8'sd2; golden_kernel[4] =  8'sd0; golden_kernel[5] =  8'sd2;
        golden_kernel[6] = -8'sd1; golden_kernel[7] =  8'sd0; golden_kernel[8] =  8'sd1;

        // Sinh ma tran anh gia lap voi cac gia tri signed INT8 (-128..127)
        for (int r = 0; r < 32; r++) begin
            for (int c = 0; c < 32; c++) begin
                golden_image[r][c] = 8'($dist_uniform(seed, -128, 127));
            end
        end

        // 2. Reset he thong ban dau
        rst          = 1'b1;
        ibuf_wr_en   = 1'b0;
        ibuf_wr_addr = 10'd0;
        ibuf_wr_data = 8'sd0;
        wbuf_wr_en   = 1'b0;
        wbuf_wr_addr = 4'd0;
        wbuf_wr_data = 8'sd0;
        start_window = 1'b0;
        out_row      = 5'd0;
        out_col      = 5'd0;

        repeat (4) @(posedge clk);
        #1;
        if (busy !== 1'b0 || window_done !== 1'b0 || window_result !== 32'sd0) begin
            $display("[FAIL] Reset ban dau that bai!");
            $fatal(1);
        end
        @(negedge clk);
        rst = 1'b0;

        // 3. Nap Input Buffer va Weight Buffer
        load_buffers();

        // 4. KIEM TRA CAC CUA SO QUAN TRONG (THEO YEU CAU):
        $display("\n>>> [2] Kiem tra cac cua so tieu bieu tren anh 32x32...");

        // A. Cua so DAU ANH (Top-Left): row=0, col=0
        test_single_window("TEST_1_TOP_LEFT", 5'd0, 5'd0);

        // B. Cua so GIUA ANH (Center): row=14, col=14
        test_single_window("TEST_2_CENTER", 5'd14, 5'd14);

        // C. Cua so CUOI ANH (Bottom-Right): row=29, col=29
        test_single_window("TEST_3_BOTTOM_RIGHT", 5'd29, 5'd29);

        // D. Cua so GOC TREN PHAI (Top-Right): row=0, col=29
        test_single_window("TEST_4_TOP_RIGHT", 5'd0, 5'd29);

        // E. Cua so GOC DUOI TRAI (Bottom-Left): row=29, col=0
        test_single_window("TEST_5_BOTTOM_LEFT", 5'd29, 5'd0);

        // 5. KIEM TRA HOI QUY NGAU NHIEN THEM 15 CUA SO BAT KY:
        $display("\n>>> [3] Kiem tra hoi quy ngau nhien 15 vi tri cua so bat ky...");
        for (int t = 1; t <= 15; t++) begin
            logic [4:0] rand_r, rand_c;
            rand_r = 5'($dist_uniform(seed, 0, 29));
            rand_c = 5'($dist_uniform(seed, 0, 29));
            test_single_window($sformatf("RAND_WINDOW_%02d", t), rand_r, rand_c);
        end

        // 6. TONG KET KET QUA
        $display("\n==================================================================");
        $display("   KET QUA KIEM CHUNG GIAI DOAN 3 (conv_window_reader):");
        $display("   - Tong so cua so da kiem tra:  %0d", total_windows_tested);
        $display("   - So cua so tinh toan dung:    %0d", total_windows_passed);
        $display("   - So cua so that bai:          %0d", total_windows_failed);
        $display("   - Tong so cap toan hang kiem tra: %0d / %0d", total_pair_checks, total_windows_tested * 9);
        $display("==================================================================");

        if (total_windows_failed == 0 && total_windows_tested >= 20) begin
            $display(">>> [SUCCESS] TAT CA CAC TESTBENCH GIAI DOAN 3 DA PASS 100%%!");
            $display(">>> Waveform VCD da luu tai: build/conv_window_reader_waveform.vcd");
        end else begin
            $display(">>> [FAILURE] CO TESTBENCH GIAI DOAN 3 THAT BAI!");
            $fatal(1);
        end

        $finish;
    end

endmodule
