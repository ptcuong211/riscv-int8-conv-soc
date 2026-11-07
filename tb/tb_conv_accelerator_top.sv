// ============================================================================
// Module Name: tb_conv_accelerator_top
// Description: Comprehensive Self-Checking Testbench for conv_accelerator_top (Stage 5)
// Target:      RISC-V INT8 Convolution Accelerator
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module tb_conv_accelerator_top;

    // ------------------------------------------------------------------------
    // Thong so cau hinh
    // ------------------------------------------------------------------------
    localparam int IMG_WIDTH     = 32;
    localparam int IMG_HEIGHT    = 32;
    localparam int KERNEL_SIZE   = 3;
    localparam int OUT_WIDTH     = IMG_WIDTH - KERNEL_SIZE + 1; // 30
    localparam int OUT_HEIGHT    = IMG_HEIGHT - KERNEL_SIZE + 1; // 30
    localparam int TOTAL_OUTPUTS = OUT_WIDTH * OUT_HEIGHT;       // 900
    localparam int CLK_PERIOD    = 10;                          // 100 MHz (10ns period)

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

    // Cong doc Output Buffer
    logic [9:0]              obuf_rd_addr;
    logic signed [31:0]      obuf_rd_data;

    // ------------------------------------------------------------------------
    // Golden Reference Model doc lap trong Testbench
    // ------------------------------------------------------------------------
    logic signed [7:0]  golden_image[0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    logic signed [7:0]  golden_kernel[0:8];
    logic signed [31:0] golden_output[0:TOTAL_OUTPUTS-1];

    // Bien thong ke kiem chung
    int test_pass_count = 0;
    int test_fail_count = 0;

    // ------------------------------------------------------------------------
    // Tao xung clock 100 MHz
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Khoi tao DUT (conv_accelerator_top)
    // Tich hop toan bo phan cung tu Stage 1 toi Stage 5
    // ------------------------------------------------------------------------
    conv_accelerator_top #(
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
        .obuf_rd_addr (obuf_rd_addr),
        .obuf_rd_data (obuf_rd_data)
    );

    // ------------------------------------------------------------------------
    // Dump Waveform VCD (Top-level & control signals)
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("conv_accelerator_top_waveform.vcd");
        $dumpvars(1, tb_conv_accelerator_top);
        $dumpvars(2, u_dut);
    end

    // ------------------------------------------------------------------------
    // Task tinh toan Golden Model 2D Convolution doc lap
    // ------------------------------------------------------------------------
    task automatic compute_golden();
        for (int r = 0; r < OUT_HEIGHT; r++) begin
            for (int c = 0; c < OUT_WIDTH; c++) begin
                int signed sum = 0;
                for (int kr = 0; kr < KERNEL_SIZE; kr++) begin
                    for (int kc = 0; kc < KERNEL_SIZE; kc++) begin
                        int signed px = int'(signed'(golden_image[r + kr][c + kc]));
                        int signed wt = int'(signed'(golden_kernel[kr * 3 + kc]));
                        sum += px * wt;
                    end
                end
                golden_output[r * OUT_WIDTH + c] = 32'(sum);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Task nap anh vao Input Buffer
    // ------------------------------------------------------------------------
    task automatic load_input_image();
        @(posedge clk);
        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                ibuf_wr_en   <= 1'b1;
                ibuf_wr_addr <= 10'(r * IMG_WIDTH + c);
                ibuf_wr_data <= golden_image[r][c];
                @(posedge clk);
            end
        end
        ibuf_wr_en   <= 1'b0;
        ibuf_wr_addr <= '0;
        ibuf_wr_data <= '0;
    endtask

    // ------------------------------------------------------------------------
    // Task nap kernel vao Weight Buffer
    // ------------------------------------------------------------------------
    task automatic load_kernel_weights();
        @(posedge clk);
        for (int i = 0; i < 9; i++) begin
            wbuf_wr_en   <= 1'b1;
            wbuf_wr_addr <= 4'(i);
            wbuf_wr_data <= golden_kernel[i];
            @(posedge clk);
        end
        wbuf_wr_en   <= 1'b0;
        wbuf_wr_addr <= '0;
        wbuf_wr_data <= '0;
    endtask

    // ------------------------------------------------------------------------
    // Task doc va kiem chung toan bo 900 ket qua tu Output Buffer
    // Tuan thu dung 1-cycle latency cua Synchronous Read BRAM
    // ------------------------------------------------------------------------
    task automatic verify_output_buffer(input string test_name);
        int mismatch_count = 0;

        @(posedge clk);
        // Thiet lap doc phan tu 0
        obuf_rd_addr <= 10'd0;
        @(posedge clk); // Sau canh clock nay, data tai addr 0 xuat hien tai obuf_rd_data

        for (int i = 0; i < TOTAL_OUTPUTS; i++) begin
            if (i + 1 < TOTAL_OUTPUTS) begin
                obuf_rd_addr <= 10'(i + 1);
            end
            #1; // Lay mau du lieu sau posedge clock
            if (obuf_rd_data !== golden_output[i]) begin
                if (mismatch_count < 10) begin
                    $display("[FAIL] %s | Addr: %0d (Row %0d, Col %0d) | Got: %0d != Exp: %0d",
                             test_name, i, i / OUT_WIDTH, i % OUT_WIDTH, obuf_rd_data, golden_output[i]);
                end
                mismatch_count++;
            end
            @(posedge clk);
        end
        obuf_rd_addr <= 10'd0;

        if (mismatch_count == 0) begin
            $display("[PASS] %s: Toan bo %0d/%0d outputs trong Output Buffer khop 100%% voi Golden Reference!",
                     test_name, TOTAL_OUTPUTS, TOTAL_OUTPUTS);
            test_pass_count++;
        end else begin
            $display("[FAIL] %s: Phat hien %0d / %0d outputs bi sai!",
                     test_name, mismatch_count, TOTAL_OUTPUTS);
            test_fail_count++;
        end
    endtask

    // ------------------------------------------------------------------------
    // Task thuc thi 1 chu trinh chay hoan chinh: Start -> Wait Done -> Verify
    // ------------------------------------------------------------------------
    task automatic run_convolution_and_verify(input string test_name);
        $display("\n>>> Bat dau chay %s...", test_name);
        compute_golden();
        load_input_image();
        load_kernel_weights();

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Kiem tra tin hieu busy
        #1;
        if (!busy) begin
            $display("[WARN] %s: busy chua tich cuc ngay sau start!", test_name);
        end

        // Cho accelerator hoan tat (xung done)
        @(posedge done);
        $display("[INFO] %s: Nhan duoc tin hieu done tu Accelerator!", test_name);

        // Kiem tra Output Buffer
        verify_output_buffer(test_name);
    endtask

    // ------------------------------------------------------------------------
    // Chuong trinh kiem thu chinh
    // ------------------------------------------------------------------------
    initial begin
        $display("==================================================================");
        $display("   BAT DAU KIEM THU CONV_ACCELERATOR_TOP (STAGE 5)");
        $display("==================================================================");

        // Khoi tao tin hieu
        rst          = 1'b1;
        start        = 1'b0;
        ibuf_wr_en   = 1'b0;
        ibuf_wr_addr = '0;
        ibuf_wr_data = '0;
        wbuf_wr_en   = 1'b0;
        wbuf_wr_addr = '0;
        wbuf_wr_data = '0;
        obuf_rd_addr = '0;

        #(CLK_PERIOD * 5);
        rst = 1'b0;
        #(CLK_PERIOD * 2);

        // ====================================================================
        // TEST 1: Zero Input
        // ====================================================================
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = 8'sd0;

        golden_kernel[0] = 8'sd5;  golden_kernel[1] = -8'sd3; golden_kernel[2] = 8'sd2;
        golden_kernel[3] = -8'sd1; golden_kernel[4] = 8'sd4;  golden_kernel[5] = -8'sd2;
        golden_kernel[6] = 8'sd3;  golden_kernel[7] = 8'sd1;  golden_kernel[8] = -8'sd5;

        run_convolution_and_verify("TEST 1 (Zero Input)");

        // ====================================================================
        // TEST 2: All Ones (Input = 1, Kernel = 1, Expected = 9)
        // ====================================================================
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = 8'sd1;

        for (int i = 0; i < 9; i++)
            golden_kernel[i] = 8'sd1;

        run_convolution_and_verify("TEST 2 (All Ones)");

        // ====================================================================
        // TEST 3: Sequential Pattern (Linear Ramp & Sobel Filter)
        // ====================================================================
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = signed'(8'(((r * IMG_WIDTH + c) % 127) - 64));

        golden_kernel[0] = -8'sd1; golden_kernel[1] = 8'sd0; golden_kernel[2] = 8'sd1;
        golden_kernel[3] = -8'sd2; golden_kernel[4] = 8'sd0; golden_kernel[5] = 8'sd2;
        golden_kernel[6] = -8'sd1; golden_kernel[7] = 8'sd0; golden_kernel[8] = 8'sd1;

        run_convolution_and_verify("TEST 3 (Sequential Pattern)");

        // ====================================================================
        // TEST 4: Negative Values & Extreme Signs
        // ====================================================================
        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                if ((r + c) % 2 == 0)
                    golden_image[r][c] = -8'sd120;
                else
                    golden_image[r][c] = 8'sd110;
            end
        end

        golden_kernel[0] = -8'sd10; golden_kernel[1] = 8'sd20;  golden_kernel[2] = -8'sd30;
        golden_kernel[3] = 8'sd40;  golden_kernel[4] = -8'sd50; golden_kernel[5] = 8'sd60;
        golden_kernel[6] = -8'sd70; golden_kernel[7] = 8'sd80;  golden_kernel[8] = -8'sd90;

        run_convolution_and_verify("TEST 4 (Negative & Mixed Values)");

        // ====================================================================
        // TEST 5: Random Input & Random Kernel
        // ====================================================================
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = signed'(8'($urandom_range(0, 255) - 128));

        for (int i = 0; i < 9; i++)
            golden_kernel[i] = signed'(8'($urandom_range(0, 255) - 128));

        run_convolution_and_verify("TEST 5 (Random Input & Kernel)");

        // ====================================================================
        // TEST 6: Output Address Integrity (Check Monotonicity & Complete 0..899)
        // ====================================================================
        $display("\n>>> TEST 6: Output Address Integrity...");
        begin
            int addr_integrity_err = 0;
            // Kiem tra lai ket qua cua TEST 5 theo dung tung dia chi tuyen tinh 0..899
            for (int r = 0; r < OUT_HEIGHT; r++) begin
                for (int c = 0; c < OUT_WIDTH; c++) begin
                    int linear_addr = r * OUT_WIDTH + c;
                    @(posedge clk);
                    obuf_rd_addr <= 10'(linear_addr);
                    @(posedge clk);
                    #1;
                    if (obuf_rd_data !== golden_output[linear_addr]) begin
                        addr_integrity_err++;
                    end
                end
            end
            obuf_rd_addr <= 10'd0;

            if (addr_integrity_err == 0) begin
                $display("[PASS] TEST 6: Dia chi Output Buffer 0..899 hoan toan toan ven va nhat quan theo Raster Order!");
                test_pass_count++;
            end else begin
                $display("[FAIL] TEST 6: Co %0d dia chi bi sai!", addr_integrity_err);
                test_fail_count++;
            end
        end

        // ====================================================================
        // TEST 7: Start/Busy Control & Protection against Spurious Start
        // ====================================================================
        $display("\n>>> TEST 7: Start/Busy Control & Spurious Start Rejection...");
        begin
            int spurious_pass = 1;
            // Kiem tra trang thai ban dau
            if (busy !== 1'b0) begin
                $display("[FAIL] TEST 7.1: Khi ranh, busy phai bang 0!");
                spurious_pass = 0;
            end

            // Phat xung start
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            // Kiem tra busy da len 1
            #1;
            if (busy !== 1'b1) begin
                $display("[FAIL] TEST 7.2: busy phai len 1 ngay sau xung start!");
                spurious_pass = 0;
            end

            // Trong khi dang busy, phat them cac xung start khong hop le
            repeat (50) @(posedge clk);
            if (busy == 1'b1) begin
                start <= 1'b1; // Gui xung start khi dang bận
                @(posedge clk);
                start <= 1'b0;
            end

            // Cho accelerator hoan thanh binh thuong
            @(posedge done);
            @(posedge clk);
            #1;
            // Sau khi done, busy phai tro ve 0 o chu ky ke tiep
            if (busy !== 1'b0) begin
                $display("[FAIL] TEST 7.3: Sau khi hoan tat, busy phai tro ve 0!");
                spurious_pass = 0;
            end

            if (spurious_pass) begin
                $display("[PASS] TEST 7: Start/Busy hoat dong chuan xac, bo qua an toan xung start khi busy!");
                test_pass_count++;
            end else begin
                test_fail_count++;
            end
        end

        // ====================================================================
        // TEST 8: Reset Behavior (Before and During Processing)
        // ====================================================================
        $display("\n>>> TEST 8: Reset Behavior (Before & Mid-Execution)...");
        begin
            int reset_pass = 1;

            // 8.1. Reset truoc khi chay
            @(posedge clk);
            rst <= 1'b1;
            @(posedge clk);
            rst <= 1'b0;
            #1;
            if (busy !== 1'b0 || done !== 1'b0) begin
                $display("[FAIL] TEST 8.1: Sau reset, busy va done phai bang 0!");
                reset_pass = 0;
            end

            // 8.2. Reset giua chung khi dang tinh toan
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            // Cho chay 100 chu ky roi cat ngang bang reset
            repeat (100) @(posedge clk);
            @(posedge clk);
            rst <= 1'b1;
            @(posedge clk);
            rst <= 1'b0;
            #1;
            if (busy !== 1'b0 || done !== 1'b0) begin
                $display("[FAIL] TEST 8.2: Sau reset giua chung, accelerator phai ngay lap tuc ve IDLE!");
                reset_pass = 0;
            end

            // 8.3. Chay lai binh thuong sau reset de chung minh he thong phuc hoi hoan toan
            run_convolution_and_verify("TEST 8.3 (Recovery after Mid-Execution Reset)");

            if (reset_pass) begin
                $display("[PASS] TEST 8: Xu ly Reset hoan toan an toan va phuc hoi chuan xac 100%%!");
                test_pass_count++;
            end else begin
                test_fail_count++;
            end
        end

        // ====================================================================
        // TEST 9: Re-run Accelerator with New Dataset
        // ====================================================================
        $display("\n>>> TEST 9: Re-run Accelerator with Brand New Dataset...");
        // Nap toan bo du lieu hoan toan moi de kiem tra viec ghi de Output Buffer
        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                golden_image[r][c] = signed'(8'(c - r));

        golden_kernel[0] = 8'sd2;  golden_kernel[1] = 8'sd3;  golden_kernel[2] = 8'sd2;
        golden_kernel[3] = 8'sd0;  golden_kernel[4] = -8'sd4; golden_kernel[5] = 8'sd0;
        golden_kernel[6] = -8'sd2; golden_kernel[7] = -8'sd3; golden_kernel[8] = -8'sd2;

        run_convolution_and_verify("TEST 9 (Re-run Accelerator with Brand New Dataset)");

        // ====================================================================
        // Tong ket kiem chung toan dien Stage 5
        // ====================================================================
        $display("\n==================================================================");
        $display("   TONG KET KIEM CHUNG CONV_ACCELERATOR_TOP (STAGE 5)");
        $display("   So testcase PASS: %0d", test_pass_count);
        $display("   So testcase FAIL: %0d", test_fail_count);
        $display("==================================================================");

        if (test_fail_count == 0) begin
            $display(">>> TAT CA CAC TESTBENCH STAGE 5 DA PASS 100%%! <<<");
        end else begin
            $display(">>> CO TESTBENCH STAGE 5 BI THAT BAI! <<<");
        end

        $finish;
    end

endmodule

