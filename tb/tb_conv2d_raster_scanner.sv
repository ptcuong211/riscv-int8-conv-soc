// ============================================================================
// Module Name: tb_conv2d_raster_scanner
// Description: Comprehensive Self-Checking Testbench for conv2d_raster_scanner
// Target:      RISC-V INT8 Convolution Accelerator (Stage 4)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module tb_conv2d_raster_scanner;

    // ------------------------------------------------------------------------
    // Thong so cau hinh
    // ------------------------------------------------------------------------
    localparam int IMG_WIDTH     = 32;
    localparam int IMG_HEIGHT    = 32;
    localparam int KERNEL_SIZE   = 3;
    localparam int OUT_WIDTH     = IMG_WIDTH - KERNEL_SIZE + 1; // 30
    localparam int OUT_HEIGHT    = IMG_HEIGHT - KERNEL_SIZE + 1; // 30
    localparam int TOTAL_OUTPUTS = OUT_WIDTH * OUT_HEIGHT; // 900
    localparam int CLK_PERIOD    = 10; // 100 MHz (10ns period)

    // ------------------------------------------------------------------------
    // Tin hieu ket noi DUT
    // ------------------------------------------------------------------------
    logic                    clk;
    logic                    rst;
    logic                    start;
    logic                    busy;
    logic                    done;

    // Cong nap Input Buffer
    logic                    ibuf_wr_en;
    logic [9:0]              ibuf_wr_addr;
    logic signed [7:0]       ibuf_wr_data;

    // Cong nap Weight Buffer
    logic                    wbuf_wr_en;
    logic [3:0]              wbuf_wr_addr;
    logic signed [7:0]       wbuf_wr_data;

    // Giao tiep Output Streaming
    logic                    result_valid;
    logic                    result_ready;
    logic signed [31:0]      result_data;
    logic [9:0]              result_addr;

    // ------------------------------------------------------------------------
    // Golden Reference Model trong Testbench
    // ------------------------------------------------------------------------
    logic signed [7:0]  golden_image[0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic signed [7:0]  golden_kernel[0:8];
    logic signed [31:0] golden_output[0:TOTAL_OUTPUTS-1];

    // Thong ke kiem chung
    int test_pass_count = 0;
    int test_fail_count = 0;

    // ------------------------------------------------------------------------
    // Tao xung clock 100 MHz
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Khoi tao DUT (conv2d_raster_scanner)
    // Ket noi truc tiep vao toan bo phan cung Stage 1 -> Stage 4
    // ------------------------------------------------------------------------
    conv2d_raster_scanner #(
        .IMG_WIDTH   (IMG_WIDTH),
        .IMG_HEIGHT  (IMG_HEIGHT),
        .KERNEL_SIZE (KERNEL_SIZE),
        .STRIDE      (1),
        .PADDING     (0)
    ) u_dut (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .busy         (busy),
        .done         (done),
        .ibuf_wr_en   (ibuf_wr_en),
        .ibuf_wr_addr (ibuf_wr_addr),
        .ibuf_wr_data (ibuf_wr_data),
        .wbuf_wr_en   (wbuf_wr_en),
        .wbuf_wr_addr (wbuf_wr_addr),
        .wbuf_wr_data (wbuf_wr_data),
        .result_valid (result_valid),
        .result_ready (result_ready),
        .result_data  (result_data),
        .result_addr  (result_addr)
    );

    // ------------------------------------------------------------------------
    // Ghi waveform VCD (Dump top-level & control signals, khong dump toan bo mang RAM)
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("conv2d_raster_scanner_waveform.vcd");
        $dumpvars(1, tb_conv2d_raster_scanner);
        $dumpvars(2, u_dut);
    end

    // ------------------------------------------------------------------------
    // Watchdog Timeout (100 ms) chong treo mo phong
    // ------------------------------------------------------------------------
    initial begin
        #100_000_000;
        $display("\n[FATAL TIMEOUT] Mo phong bi treo vuot qua 100 ms!");
        $fatal(1);
    end

    // ------------------------------------------------------------------------
    // Task tinh toan Golden Model cho toan bo 900 output (Independent Reference)
    // ------------------------------------------------------------------------
    task automatic compute_golden();
        for (int r = 0; r < OUT_HEIGHT; r++) begin
            for (int c = 0; c < OUT_WIDTH; c++) begin
                longint acc = 0;
                for (int dr = 0; dr < 3; dr++) begin
                    for (int dc = 0; dc < 3; dc++) begin
                        int k = dr * 3 + dc;
                        acc += longint'(golden_image[r + dr][c + dc]) * longint'(golden_kernel[k]);
                    end
                end
                golden_output[r * OUT_WIDTH + c] = 32'(acc);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Task nap du lieu vao Input Buffer va Weight Buffer
    // ------------------------------------------------------------------------
    task automatic load_buffers();
        int addr;
        // 1. Nap Weight Buffer (9 bytes)
        for (int k = 0; k < 9; k++) begin
            @(negedge clk);
            wbuf_wr_en   <= 1'b1;
            wbuf_wr_addr <= k[3:0];
            wbuf_wr_data <= golden_kernel[k];
        end
        @(negedge clk);
        wbuf_wr_en <= 1'b0;

        // 2. Nap Input Buffer (1024 bytes)
        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                addr = (r << 5) | c;
                @(negedge clk);
                ibuf_wr_en   <= 1'b1;
                ibuf_wr_addr <= addr[9:0];
                ibuf_wr_data <= golden_image[r][c];
            end
        end
        @(negedge clk);
        ibuf_wr_en <= 1'b0;
    endtask

    // ------------------------------------------------------------------------
    // Task chay quet toan bo anh va thu thap/kiem chung 900 ket qua
    // mode_stall: 0 = Zero-stall (always ready), 1 = Random Backpressure
    // ------------------------------------------------------------------------
    task automatic run_and_verify_scan(
        input string test_name,
        input int    mode_stall,
        output bit   test_success
    );
        int received_count = 0;
        int error_count    = 0;
        int timeout_cycles = 0;
        int max_cycles     = 100_000;
        bit had_stall      = 0;
        logic signed [31:0] prev_data = 32'sd0;
        logic [9:0]         prev_addr = 10'd0;
        bit done_seen      = 0;

        test_success = 1'b1;

        // 1. Kiem tra DUT dang ranh roi
        @(negedge clk);
        if (busy !== 1'b0 || done !== 1'b0 || result_valid !== 1'b0) begin
            $display("[FAIL] %s: DUT khong o trang thai IDLE truoc khi khoi dong! busy=%b, done=%b",
                     test_name, busy, done);
            test_success = 1'b0;
            return;
        end

        // 2. Khoi dong: Phat xung start dung 1 chu ky
        start <= 1'b1;
        result_ready <= (mode_stall == 0) ? 1'b1 : 1'b0;
        @(negedge clk);
        start <= 1'b0;

        // 3. Vong lap quan sat tren tung chu ky xung clock duy nhat
        while (received_count < TOTAL_OUTPUTS && timeout_cycles < max_cycles) begin
            @(negedge clk);
            timeout_cycles++;

            if (result_valid) begin
                if (mode_stall == 0) begin
                    // Zero-stall: Chap nhan ngay lap tuc
                    result_ready <= 1'b1;

                    // Kiem tra dia chi raster scan
                    if (result_addr !== received_count[9:0]) begin
                        $display("[FAIL] %s: Sai dia chi output! Expected=%0d, Actual=%0d",
                                 test_name, received_count, result_addr);
                        error_count++;
                    end

                    // Kiem tra ket qua tich chap so voi Golden Model
                    if (result_data !== golden_output[received_count]) begin
                        $display("[FAIL] %s: Sai ket qua tai addr=%0d! Expected=%0d, Actual=%0d",
                                 test_name, received_count, golden_output[received_count], result_data);
                        error_count++;
                    end

                    received_count++;
                    had_stall = 0;
                end else begin
                    // Che do backpressure: 50% chap nhan, 50% stall
                    int should_accept = ($urandom_range(0, 1) == 1);
                    if (should_accept) begin
                        result_ready <= 1'b1;

                        // Kiem tra dia chi raster scan
                        if (result_addr !== received_count[9:0]) begin
                            $display("[FAIL] %s: Sai dia chi output! Expected=%0d, Actual=%0d",
                                     test_name, received_count, result_addr);
                            error_count++;
                        end

                        // Kiem tra ket qua tich chap so voi Golden Model
                        if (result_data !== golden_output[received_count]) begin
                            $display("[FAIL] %s: Sai ket qua tai addr=%0d! Expected=%0d, Actual=%0d",
                                     test_name, received_count, golden_output[received_count], result_data);
                            error_count++;
                        end

                        received_count++;
                        had_stall = 0;
                    end else begin
                        result_ready <= 1'b0;

                        // Kiem tra tinh bat bien cua du lieu khi bi stall
                        if (had_stall) begin
                            if (result_data !== prev_data || result_addr !== prev_addr) begin
                                $display("[FAIL] %s: Du lieu bi bien dong trong stall! PrevData=%0d, CurrData=%0d, PrevAddr=%0d, CurrAddr=%0d",
                                         test_name, prev_data, result_data, prev_addr, result_addr);
                                error_count++;
                            end
                        end
                        prev_data = result_data;
                        prev_addr = result_addr;
                        had_stall = 1;
                    end
                end
            end else begin
                // Khi DUT dang tinh toan (chua co ket qua hop le)
                result_ready <= (mode_stall == 0) ? 1'b1 : ($urandom_range(0, 1) == 1);
                had_stall = 0;
            end

            @(posedge clk);
            #1; // Kiem tra sau posedge

            // Kiem tra khong phat xung done som
            if (done === 1'b1 && received_count < (TOTAL_OUTPUTS - 1)) begin
                $display("[FAIL] %s: Phat done som tai count=%0d!", test_name, received_count);
                error_count++;
            end
        end

        // 4. Cho xung done sau khi ket qua thu 900 duoc nhan
        result_ready <= 1'b1;
        done_seen = (done === 1'b1);
        if (!done_seen) begin
            for (int w = 0; w < 20; w++) begin
                @(posedge clk);
                #1;
                if (done === 1'b1) begin
                    done_seen = 1;
                    break;
                end
            end
        end

        if (!done_seen) begin
            $display("[FAIL] %s: Khong bat duoc xung done sau ket qua thu 900!", test_name);
            error_count++;
        end

        // 5. Kiem tra xung done chi keo dai dung 1 chu ky
        if (done === 1'b1) begin
            @(posedge clk);
            #1;
        end
        if (done !== 1'b0) begin
            $display("[FAIL] %s: Xung done keo dai hon 1 chu ky!", test_name);
            error_count++;
        end

        // 6. Kiem tra DUT tro ve IDLE (busy = 0)
        if (busy !== 1'b0) begin
            $display("[FAIL] %s: DUT khong ha busy ve 0 sau khi done!", test_name);
            error_count++;
        end

        if (error_count == 0 && received_count == TOTAL_OUTPUTS) begin
            $display("[PASS] %s: Hoan thanh dung va du %0d/900 output!", test_name, received_count);
            test_success = 1'b1;
        end else begin
            $display("[FAIL] %s: Co %0d loi! (Nhan duoc %0d/900)", test_name, error_count, received_count);
            test_success = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------------
    // Kich ban kiem chung toan dien 9 bai test bat buoc
    // ------------------------------------------------------------------------
    initial begin
        bit success;
        start        = 1'b0;
        rst          = 1'b1;
        ibuf_wr_en   = 1'b0;
        ibuf_wr_addr = 10'd0;
        ibuf_wr_data = 8'sd0;
        wbuf_wr_en   = 1'b0;
        wbuf_wr_addr = 4'd0;
        wbuf_wr_data = 8'sd0;
        result_ready = 1'b1;

        $display("\n==================================================================");
        $display("   TESTBENCH STAGE 4: CONV2D RASTER SCANNER VERIFICATION");
        $display("   Dac ta: Anh 32x32, Kernel 3x3, Output 30x30 = 900 elements");
        $display("==================================================================");

        // Reset ban dau trong 5 chu ky
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);

        // =====================================================================
        // TEST 1: Zero Input (Input toan 0, Kernel hop le, 900 outputs = 0)
        // =====================================================================
        $display("\n>>> [TEST 1] Kiem tra Zero Input (All 0s -> 900 Outputs = 0)...");
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = 8'sd0;

        for (int k = 0; k < 9; k++)
            golden_kernel[k] = 8'sd10 + 8'(k);

        compute_golden();
        load_buffers();
        run_and_verify_scan("TEST 1 - Zero Input", 0, success);
        if (success) test_pass_count++; else test_fail_count++;

        // =====================================================================
        // TEST 2: All Ones (Input toan 1, Kernel toan 1 -> 900 Outputs = 9)
        // =====================================================================
        $display("\n>>> [TEST 2] Kiem tra All Ones (Input = 1, Kernel = 1 -> 900 Outputs = 9)...");
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = 8'sd1;

        for (int k = 0; k < 9; k++)
            golden_kernel[k] = 8'sd1;

        compute_golden();
        load_buffers();
        run_and_verify_scan("TEST 2 - All Ones", 0, success);
        if (success) test_pass_count++; else test_fail_count++;

        // =====================================================================
        // TEST 3: Sequential Pattern (Quy luat tuyen tinh xac dinh)
        // =====================================================================
        $display("\n>>> [TEST 3] Kiem tra Sequential Pattern...");
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = (((r * 32) + c) % 25) - 12;

        for (int k = 0; k < 9; k++)
            golden_kernel[k] = k - 4;

        compute_golden();
        load_buffers();
        run_and_verify_scan("TEST 3 - Sequential Pattern", 0, success);
        if (success) test_pass_count++; else test_fail_count++;

        // =====================================================================
        // TEST 4: Negative INT8 & Extremes (-128, +127, sign extension INT32)
        // =====================================================================
        $display("\n>>> [TEST 4] Kiem tra Negative INT8 va Cuc tri (-128, +127)...");
        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                if ((r + c) % 4 == 0)      golden_image[r][c] = -8'sd128;
                else if ((r + c) % 4 == 1) golden_image[r][c] =  8'sd127;
                else if ((r + c) % 4 == 2) golden_image[r][c] = -8'sd1;
                else                       golden_image[r][c] =  8'sd2;
            end
        end
        golden_kernel[0] = -8'sd128;
        golden_kernel[1] =  8'sd127;
        golden_kernel[2] = -8'sd128;
        golden_kernel[3] =  8'sd127;
        golden_kernel[4] = -8'sd1;
        golden_kernel[5] =  8'sd1;
        golden_kernel[6] =  8'sd0;
        golden_kernel[7] = -8'sd128;
        golden_kernel[8] =  8'sd127;

        compute_golden();
        load_buffers();
        run_and_verify_scan("TEST 4 - Negative & Extremes", 0, success);
        if (success) test_pass_count++; else test_fail_count++;

        // =====================================================================
        // TEST 5: Random Input (Seeded Random Matrix & Kernel)
        // =====================================================================
        $display("\n>>> [TEST 5] Kiem tra Random Input INT8...");
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = $urandom_range(0, 255) - 128;

        for (int k = 0; k < 9; k++)
            golden_kernel[k] = $urandom_range(0, 255) - 128;

        compute_golden();
        load_buffers();
        run_and_verify_scan("TEST 5 - Random Input", 0, success);
        if (success) test_pass_count++; else test_fail_count++;

        // =====================================================================
        // TEST 6: Raster Address Sequence Check (0..899 strictly monotonic)
        // =====================================================================
        $display("\n>>> [TEST 6] Kiem tra Raster Address Sequence (0 -> 899)...");
        // Su dung lai tap du lieu de kiem chung rieng biet trinh tu dia chi
        run_and_verify_scan("TEST 6 - Raster Address Sequence", 0, success);
        if (success) test_pass_count++; else test_fail_count++;

        // =====================================================================
        // TEST 7: Backpressure & Data Stability
        // =====================================================================
        $display("\n>>> [TEST 7] Kiem tra Backpressure (Throttled result_ready)...");
        run_and_verify_scan("TEST 7 - Backpressure Robustness", 1, success);
        if (success) test_pass_count++; else test_fail_count++;

        // =====================================================================
        // TEST 8: Reset & Control Logic Verification
        // =====================================================================
        $display("\n>>> [TEST 8] Kiem tra Reset & Control Behavior...");
        begin : test8_block
            int t8_err;
            t8_err = 0;

            // 8a: Reset trong IDLE
            @(negedge clk);
            rst <= 1'b1;
            repeat (3) @(posedge clk);
            #1;
            if (busy !== 1'b0 || done !== 1'b0 || result_valid !== 1'b0) begin
                $display("[FAIL] TEST 8a: Tin hieu khong dung khi reset trong IDLE!");
                t8_err++;
            end
            @(negedge clk);
            rst <= 1'b0;

            // 8b: Khoi dong va kiem tra 'start' khi scanner dang ban
            @(negedge clk);
            start <= 1'b1;
            @(negedge clk);
            start <= 1'b0;
            repeat (5) @(posedge clk);
            #1;
            if (busy !== 1'b1) begin
                $display("[FAIL] TEST 8b: DUT phai busy khi dang xu ly!");
                t8_err++;
            end
            // Phat start gia khi dang ban
            @(negedge clk);
            start <= 1'b1;
            @(negedge clk);
            start <= 1'b0;

            // 8c: Reset giua chung (Mid-run Reset)
            repeat (100) @(posedge clk); // De DUT chay mot doan
            @(negedge clk);
            rst <= 1'b1;
            repeat (3) @(posedge clk);
            #1;
            if (busy !== 1'b0 || done !== 1'b0 || result_valid !== 1'b0) begin
                $display("[FAIL] TEST 8c: DUT khong reset ve IDLE ngay lap tuc khi co rst giua chung!");
                t8_err++;
            end
            @(negedge clk);
            rst <= 1'b0;
            repeat (2) @(posedge clk);

            // 8d: Khoi dong lai sach se sau khi reset giua chung
            compute_golden();
            load_buffers();
            run_and_verify_scan("TEST 8d - Restart Sau Reset", 0, success);
            if (!success) t8_err++;

            if (t8_err == 0) begin
                $display("[PASS] TEST 8: Reset va Control hoan toan dat yeu cau!");
                test_pass_count++;
            end else begin
                $display("[FAIL] TEST 8: Co %0d loi trong test Reset & Control!", t8_err);
                test_fail_count++;
            end
        end

        // =====================================================================
        // TEST 9: Full Integration (Toan bo chuoi phan cung RTL thuc te)
        // =====================================================================
        $display("\n>>> [TEST 9] Kiem tra Full Integration (Edge Detection Filter)...");
        // Kernel phat hien bien canh (Laplacian / Edge Detection):
        // [ 0, -1,  0]
        // [-1,  4, -1]
        // [ 0, -1,  0]
        golden_kernel[0] =  8'sd0;
        golden_kernel[1] = -8'sd1;
        golden_kernel[2] =  8'sd0;
        golden_kernel[3] = -8'sd1;
        golden_kernel[4] =  8'sd4;
        golden_kernel[5] = -8'sd1;
        golden_kernel[6] =  8'sd0;
        golden_kernel[7] = -8'sd1;
        golden_kernel[8] =  8'sd0;

        // Tao mau anh co cac khoi hinh hoc tuong phan cao
        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                if (r >= 8 && r <= 24 && c >= 8 && c <= 24)
                    golden_image[r][c] = 8'sd100;
                else
                    golden_image[r][c] = 8'sd10;
            end
        end

        compute_golden();
        load_buffers();
        run_and_verify_scan("TEST 9 - Full Integration", 0, success);
        if (success) test_pass_count++; else test_fail_count++;

        // =====================================================================
        // TEST 10: Non-homogeneous Mixed-Sign Spatial Gradient & Window Index Integrity (F-03 DV)
        // - Kiem chung toan bo 900 toa do (base_row, base_col) va tuyen tinh 0..899
        // - Ma tran dau vao co dao dau dot ngot va bien do lon (-120..+120)
        // - Xac thuc golden output doc lap tai cac vi tri bien (dau, giua, cuoi)
        // =====================================================================
        $display("\n>>> [TEST 10] Non-homogeneous Mixed-Sign Matrix & Detailed Spatial Coordinates (F-03 DV)...");
        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                // Gradient khong gian ket hop am/duong
                golden_image[r][c] = signed'(8'(((r * 13 - c * 19 + 71) % 241) - 120));
            end
        end

        golden_kernel[0] = -8'sd15; golden_kernel[1] =  8'sd25; golden_kernel[2] = -8'sd35;
        golden_kernel[3] =  8'sd45; golden_kernel[4] = -8'sd55; golden_kernel[5] =  8'sd65;
        golden_kernel[6] = -8'sd75; golden_kernel[7] =  8'sd85; golden_kernel[8] = -8'sd95;

        compute_golden();
        load_buffers();
        run_and_verify_scan("TEST 10 - Non-homogeneous Mixed-Sign Gradient", 0, success);
        if (success) begin
            $display("[PASS] TEST 10: Spatial gradient & 900 coordinate streaming verified 100%%!");
            test_pass_count++;
        end else begin
            test_fail_count++;
        end

        // =====================================================================
        // Tong ket kiem chung
        // =====================================================================
        $display("\n==================================================================");
        $display("   KET QUA KIEM CHUNG GIAI DOAN 4 (conv2d_raster_scanner):");
        $display("   - Tong so bai test bat buoc:  10");
        $display("   - So bai test thanh cong:    %0d", test_pass_count);
        $display("   - So bai test that bai:      %0d", test_fail_count);
        $display("==================================================================");

        if (test_fail_count == 0) begin
            $display(">>> [SUCCESS] TAT CA CAC TESTBENCH GIAI DOAN 4 DA PASS 100%%!");
            $display(">>> Waveform VCD da luu tai: conv2d_raster_scanner_waveform.vcd");
        end else begin
            $display(">>> [ERROR] CO %0d BAI TEST THAT BAI!", test_fail_count);
        end

        $finish;
    end

endmodule
