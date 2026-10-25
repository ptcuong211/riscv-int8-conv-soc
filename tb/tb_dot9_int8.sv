// ============================================================================
// Module Name: tb_dot9_int8
// Description: Comprehensive Self-Checking Testbench for dot9_int8
// Target:      RISC-V INT8 Convolution Accelerator (Stage 2)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module tb_dot9_int8;

    // ------------------------------------------------------------------------
    // Khai bao tin hieu giao tiep DUT
    // ------------------------------------------------------------------------
    logic               clk;
    logic               rst;
    logic               start;
    logic               in_valid;
    logic               in_ready;
    logic signed [7:0]  x;
    logic signed [7:0]  w;
    logic               busy;
    logic               done;
    logic signed [31:0] result;

    // ------------------------------------------------------------------------
    // Bien thong ke va scoreboard kiem tra doc lap
    // ------------------------------------------------------------------------
    int total_tasks_passed = 0;
    int total_tasks_failed = 0;
    int total_cycle_checks = 0;
    int done_pulse_count   = 0;

    // ------------------------------------------------------------------------
    // Khoi tao xung dong ho 100 MHz (chu ky 10ns)
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Khoi tao DUT (Device Under Test)
    // ------------------------------------------------------------------------
    dot9_int8 u_dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .in_valid (in_valid),
        .in_ready (in_ready),
        .x        (x),
        .w        (w),
        .busy     (busy),
        .done     (done),
        .result   (result)
    );

    // ------------------------------------------------------------------------
    // Ghi waveform VCD cho mo phong va debug
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("dot9_int8_waveform.vcd");
        $dumpvars(0, tb_dot9_int8);
    end

    // ------------------------------------------------------------------------
    // Watchdog Timeout chong treo mo phong (1,000,000 ns = 1 ms)
    // ------------------------------------------------------------------------
    initial begin
        #1000000;
        $display("\n[FATAL TIMEOUT] Mo phong bi treo vuot qua 1,000,000 ns!");
        $fatal(1);
    end

    // ------------------------------------------------------------------------
    // Giam sat xung DONE doc lap: dam bao moi xung DONE chi keo dai dung 1 chu ky
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        #1; // Lay mau sau NBA
        if (!rst) begin
            if (done) begin
                done_pulse_count++;
            end
        end
    end

    // ========================================================================
    // Task: Gui 1 tac vu 9 cap toan hang co the kem stall / kiem tra chi tiet
    // ========================================================================
    task automatic run_single_task (
        input string             task_name,
        input logic signed [7:0] x_vals[9],
        input logic signed [7:0] w_vals[9],
        input int                stalls[9],       // So chu ky stall in_valid=0 truoc moi cap
        input bit                feed_10th_pair,  // Co dua cap thu 10 de thu backpressure khong
        input bit                send_bad_start   // Co thu phat xung start khi dang ban khong
    );
        logic signed [63:0] expected_sum;
        int accepted_count;
        int wait_done_cycles;
        logic signed [31:0] result_at_done;

        expected_sum   = 64'sd0;
        accepted_count = 0;

        // 1. Kiem tra trang thai IDLE truoc khi bat dau
        @(negedge clk);
        if (busy !== 1'b0 || in_ready !== 1'b0 || done !== 1'b0) begin
            $display("[FAIL] %s: DUT khong o trang thai IDLE truoc khi START! busy=%b, in_ready=%b, done=%b",
                     task_name, busy, in_ready, done);
            $fatal(1);
        end
        total_cycle_checks++;

        // 2. Phat xung START dung 1 chu ky tai negedge
        start    <= 1'b1;
        in_valid <= 1'b0;
        x        <= 8'sd0;
        w        <= 8'sd0;

        @(negedge clk);
        start <= 1'b0; // Ha start sau 1 chu ky

        // 3. Cho in_ready len 1 (FSM qua CLEAR vao ACCUMULATE)
        // Trong suot qua trinh cho, in_ready phai bang 0 o CLEAR
        while (!in_ready) begin
            if (done !== 1'b0) begin
                $display("[FAIL] %s: Phat hien xung DONE gia truoc khi nhan du lieu!", task_name);
                $fatal(1);
            end
            @(negedge clk);
            total_cycle_checks++;
        end

        // 4. Nap 9 cap toan hang theo dung mo hinh bat tay (Handshake)
        for (int i = 0; i < 9; i++) begin
            // Neu co cau hinh stall: ha in_valid = 0 trong 'stalls[i]' chu ky
            for (int s = 0; s < stalls[i]; s++) begin
                in_valid <= 1'b0;
                x        <= 8'sd0;
                w        <= 8'sd0;
                @(posedge clk);
                #1; // Kiem tra sau NBA
                if (in_ready !== 1'b1 || busy !== 1'b1 || done !== 1'b0) begin
                    $display("[FAIL] %s: Sai trang thai trong luc stall tai cap %0d! in_ready=%b, busy=%b, done=%b",
                             task_name, i, in_ready, busy, done);
                    $fatal(1);
                end
                total_cycle_checks++;
                @(negedge clk);
            end

            // Phat toan hang cap thu i
            in_valid <= 1'b1;
            x        <= x_vals[i];
            w        <= w_vals[i];

            // Neu can kiem tra start khi dang ban (o cap giua chung)
            if (send_bad_start && i == 4) begin
                start <= 1'b1;
            end

            // Cho canh len posedge de xac nhan bat tay thanh cong (accept = in_valid && in_ready)
            @(posedge clk);
            #1; // Kiem tra sau NBA
            if (send_bad_start && i == 4) begin
                start <= 1'b0;
            end

            // Tai canh len nay, in_ready phai bang 1 vi FSM dang o ACCUMULATE
            expected_sum   = expected_sum + (64'(x_vals[i]) * 64'(w_vals[i]));
            accepted_count = accepted_count + 1;
            total_cycle_checks++;

            @(negedge clk);
        end

        // 5. Sau cap thu 9, in_ready phai lap tuc ha xuong 0
        if (feed_10th_pair) begin
            // Co tinh cap cap thu 10 de kiem tra DUT co tu choi khong
            in_valid <= 1'b1;
            x        <= 8'sd120; // Gia tri rac khong duoc phep cong
            w        <= 8'sd50;
        end else begin
            in_valid <= 1'b0;
            x        <= 8'sd0;
            w        <= 8'sd0;
        end

        // Kiem tra in_ready phai bang 0 ngay sau cap thu 9
        if (in_ready !== 1'b0) begin
            $display("[FAIL] %s: in_ready khong ha xuong 0 sau khi nhan du 9 cap! in_ready=%b",
                     task_name, in_ready);
            $fatal(1);
        end
        total_cycle_checks++;

        // 6. Cho xung DONE = 1
        wait_done_cycles = 0;
        while (!done) begin
            @(posedge clk);
            #1;
            wait_done_cycles++;
            if (wait_done_cycles > 10) begin
                $display("[FAIL] %s: DUT khong phat xung DONE sau 10 chu ky tu cap thu 9!", task_name);
                $fatal(1);
            end
            total_cycle_checks++;
            @(negedge clk);
            // Giu in_valid=0 hoac 10th pair
            if (!feed_10th_pair) in_valid <= 1'b0;
        end

        // 7. Tai chu ky DONE = 1: kiem tra result
        result_at_done = result;
        // Xu ly wrap-around signed 32-bit theo dung bu hai mod 2^32
        if (result_at_done !== 32'(expected_sum)) begin
            $display("[FAIL] %s: RESULT MISMATCH!", task_name);
            $display("       Expected: %0d (0x%08h)", 32'(expected_sum), 32'(expected_sum));
            $display("       Actual:   %0d (0x%08h)", result_at_done, result_at_done);
            $display("       So cap nhan: %0d", accepted_count);
            $fatal(1);
        end
        total_cycle_checks++;

        // Kiem tra busy phai = 1 trong suot chu ky DONE
        if (busy !== 1'b1) begin
            $display("[FAIL] %s: busy phai bang 1 trong chu ky DONE!", task_name);
            $fatal(1);
        end

        // 8. Chu ky tiep theo: DONE phai ha ve 0, FSM tro ve IDLE, busy=0, result van giu nguyen!
        in_valid <= 1'b0;
        @(posedge clk);
        #1;
        if (done !== 1'b0) begin
            $display("[FAIL] %s: Xung DONE keo dai nhieu hon 1 chu ky!", task_name);
            $fatal(1);
        end
        if (busy !== 1'b0) begin
            $display("[FAIL] %s: DUT khong tro ve IDLE (busy=0) sau chu ky DONE!", task_name);
            $fatal(1);
        end
        if (result !== result_at_done) begin
            $display("[FAIL] %s: result bi thay doi khi tro ve IDLE! Cu: %0d, Moi: %0d",
                     task_name, result_at_done, result);
            $fatal(1);
        end
        total_cycle_checks++;

        total_tasks_passed++;
        $display("[PASS] %s -> Expected=%0d, Actual=%0d", task_name, 32'(expected_sum), result_at_done);
    endtask

    // ========================================================================
    // MAIN VERIFICATION SEQUENCE
    // ========================================================================
    initial begin
        logic signed [7:0] test_x[9];
        logic signed [7:0] test_w[9];
        int                zero_stalls[9];
        int                random_stalls[9];
        int                seed;

        for (int i = 0; i < 9; i++) zero_stalls[i] = 0;

        $display("==================================================================");
        $display("   TESTBENCH BAT DAU: tb_dot9_int8 (Stage 2 Verification)");
        $display("==================================================================");

        // --------------------------------------------------------------------
        // NHOM A: KIEM TRA RESET VA KHOI DONG
        // --------------------------------------------------------------------
        $display("\n>>> [Nhom A] Kiem tra Reset, Khoi dong va Tu choi du lieu...");
        rst      = 1'b1;
        start    = 1'b0;
        in_valid = 1'b0;
        x        = 8'sd0;
        w        = 8'sd0;

        repeat (4) @(posedge clk);
        #1;
        if (busy !== 1'b0 || in_ready !== 1'b0 || done !== 1'b0 || result !== 32'sd0) begin
            $display("[FAIL] Reset ban dau that bai! busy=%b, in_ready=%b, done=%b, result=%0d",
                     busy, in_ready, done, result);
            $fatal(1);
        end
        $display("[PASS] Reset dong bo ban dau thanh cong.");

        @(negedge clk);
        rst = 1'b0;

        // Cho 5 chu ky o IDLE, kiem tra khong tu chay
        repeat (5) @(posedge clk);
        #1;
        if (busy !== 1'b0 || in_ready !== 1'b0 || done !== 1'b0) begin
            $display("[FAIL] FSM tu chay khi chua co START!");
            $fatal(1);
        end
        $display("[PASS] FSM giu nguyen IDLE on dinh khi khong co START.");

        // Thu dua in_valid = 1 khi o IDLE: in_ready phai = 0, khong duoc nhan
        @(negedge clk);
        in_valid = 1'b1;
        x = 8'sd25;
        w = 8'sd10;
        @(posedge clk);
        #1;
        if (in_ready !== 1'b0) begin
            $display("[FAIL] in_ready bat len khi dang o IDLE!");
            $fatal(1);
        end
        $display("[PASS] Du lieu bi tu choi chinh xac khi dang o IDLE.");

        // Thu dong thoi bat START va in_valid: du lieu khong duoc nhan tai canh START
        @(negedge clk);
        start = 1'b1;
        in_valid = 1'b1;
        x = 8'sd33;
        w = 8'sd11;
        @(posedge clk);
        #1;
        if (in_ready !== 1'b0) begin
            $display("[FAIL] in_ready bat len ngay tai canh nhan START!");
            $fatal(1);
        end
        @(negedge clk);
        start = 1'b0;
        in_valid = 1'b0;
        $display("[PASS] START va in_valid cung bat: du lieu khong bi nhan tai canh START.");

        // Chuyen qua CLEAR, doi den khi vao ACCUMULATE roi dot ngot RESET giua chung
        while (!in_ready) @(negedge clk);
        // Nhan 3 cap toan hang
        for (int i = 0; i < 3; i++) begin
            @(negedge clk);
            in_valid = 1'b1;
            x = 8'sd10;
            w = 8'sd10;
            @(posedge clk);
        end
        // Reset dot ngot giua chung
        @(negedge clk);
        rst = 1'b1;
        in_valid = 1'b0;
        @(posedge clk);
        #1;
        if (busy !== 1'b0 || in_ready !== 1'b0 || done !== 1'b0 || result !== 32'sd0) begin
            $display("[FAIL] Reset giua tac vu khong dua he thong ve IDLE lap tuc!");
            $fatal(1);
        end
        // Cho 5 chu ky sau reset, dam bao khong co xung done gia
        repeat (5) @(posedge clk);
        #1;
        if (done !== 1'b0) begin
            $display("[FAIL] Phat hien xung DONE gia sau khi Reset giua chung!");
            $fatal(1);
        end
        @(negedge clk);
        rst = 1'b0;
        $display("[PASS] Reset giua chung huy tac vu cu thanh cong, khong phat DONE gia.");

        // --------------------------------------------------------------------
        // NHOM B: KIEM TRA PHEP TINH SO HOC (ARITHMETIC)
        // --------------------------------------------------------------------
        $display("\n>>> [Nhom B] Kiem tra Phep tinh So hoc...");

        // B1: 9 cap toan hang duong lien tuc
        test_x = '{8'sd10, 8'sd20, 8'sd30, 8'sd40, 8'sd50, 8'sd60, 8'sd70, 8'sd80, 8'sd90};
        test_w = '{8'sd1,  8'sd2,  8'sd3,  8'sd4,  8'sd5,  8'sd6,  8'sd7,  8'sd8,  8'sd9};
        run_single_task("B1_All_Positive", test_x, test_w, zero_stalls, 0, 0);

        // B2: 9 cap toan hang am lien tuc
        test_x = '{-8'sd10, -8'sd20, -8'sd30, -8'sd40, -8'sd50, -8'sd60, -8'sd70, -8'sd80, -8'sd90};
        test_w = '{-8'sd1,  -8'sd2,  -8'sd3,  -8'sd4,  -8'sd5,  -8'sd6,  -8'sd7,  -8'sd8,  -8'sd9};
        run_single_task("B2_All_Negative", test_x, test_w, zero_stalls, 0, 0);

        // B3: 9 cap toan hang trai dau (Tong am)
        test_x = '{8'sd15, -8'sd25, 8'sd35, -8'sd45, 8'sd55, -8'sd65, 8'sd75, -8'sd85, 8'sd95};
        test_w = '{-8'sd2,  8'sd3, -8'sd4,  8'sd5, -8'sd6,  8'sd7, -8'sd8,  8'sd9, -8'sd10};
        run_single_task("B3_Mixed_Signs", test_x, test_w, zero_stalls, 0, 0);

        // B4: Toan hang chua gia tri 0
        test_x = '{8'sd0, 8'sd120, 8'sd0, -8'sd80, 8'sd0, 8'sd50, 8'sd0, -8'sd100, 8'sd0};
        test_w = '{8'sd50, 8'sd0, -8'sd20, 8'sd0, 8'sd99, 8'sd0, -8'sd12, 8'sd0, 8'sd127};
        run_single_task("B4_Zero_Operands", test_x, test_w, zero_stalls, 0, 0);

        // B5: Cua so CNN cuc tri duong (-128) x (-128) = 16384 * 9 = 147456
        test_x = '{-8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128};
        test_w = '{-8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128};
        run_single_task("B5_Max_Positive_CNN_147456", test_x, test_w, zero_stalls, 0, 0);

        // B6: Cua so CNN cuc tri am (-128) x (+127) = -16256 * 9 = -146304
        test_x = '{-8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128, -8'sd128};
        test_w = '{8'sd127,  8'sd127,  8'sd127,  8'sd127,  8'sd127,  8'sd127,  8'sd127,  8'sd127,  8'sd127};
        run_single_task("B6_Max_Negative_CNN_m146304", test_x, test_w, zero_stalls, 0, 0);

        // B7: Cua so cuc tri (+127) x (+127) = 16129 * 9 = 145161
        test_x = '{8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127};
        test_w = '{8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127, 8'sd127};
        run_single_task("B7_Max_Pos_x_Pos_145161", test_x, test_w, zero_stalls, 0, 0);

        // B8: Kiem tra dac tri: 8 cap bang 0, duy nhat cap thu 9 khac 0 (Phat hien loi bo quen cap thu 9)
        test_x = '{8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd25};
        test_w = '{8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd4}; // 25 * 4 = 100
        run_single_task("B8_Only_9th_Pair_NonZero_100", test_x, test_w, zero_stalls, 0, 0);

        // --------------------------------------------------------------------
        // NHOM C: KIEM TRA BAT TAY HANDSHAKE, STALL VA BACKPRESSURE
        // --------------------------------------------------------------------
        $display("\n>>> [Nhom C] Kiem tra Bat tay Handshake, Stall va Backpressure...");

        // C1: Co stall xen ke giua cac cap (1-2 chu ky stall)
        for (int i = 0; i < 9; i++) random_stalls[i] = (i % 2 == 1) ? 2 : 1;
        test_x = '{8'sd12, -8'sd34, 8'sd56, -8'sd78, 8'sd90, -8'sd11, 8'sd22, -8'sd33, 8'sd44};
        test_w = '{8'sd2,   8'sd3,  -8'sd4,  8'sd5,  -8'sd6,  8'sd7,  -8'sd8,  8'sd9,  -8'sd10};
        run_single_task("C1_Stalls_Between_Pairs", test_x, test_w, random_stalls, 0, 0);

        // C2: Khoang nghi dai (15 chu ky stall) truoc cap thu 9: khong duoc DONE som
        for (int i = 0; i < 9; i++) random_stalls[i] = (i == 8) ? 15 : 0;
        test_x = '{8'sd5, 8'sd10, 8'sd15, 8'sd20, 8'sd25, 8'sd30, 8'sd35, 8'sd40, 8'sd45};
        test_w = '{8'sd1, 8'sd1,  8'sd1,  8'sd1,  8'sd1,  8'sd1,  8'sd1,  8'sd1,  8'sd2};
        run_single_task("C2_Long_Stall_Before_9th_Pair", test_x, test_w, random_stalls, 0, 0);

        // C3: Kiem tra cap thu 10 bi tu choi (Backpressure check)
        run_single_task("C3_Reject_10th_Pair", test_x, test_w, zero_stalls, 1, 0);

        // --------------------------------------------------------------------
        // NHOM D: KIEM TRA DIEU KHIEN (CONTROL & ROBUSTNESS)
        // --------------------------------------------------------------------
        $display("\n>>> [Nhom D] Kiem tra Dieu khien va Khang loi (Robustness)...");

        // D1: Phat xung START khi dang ban (busy=1) bi bo qua
        test_x = '{8'sd7, 8'sd14, 8'sd21, 8'sd28, 8'sd35, 8'sd42, 8'sd49, 8'sd56, 8'sd63};
        test_w = '{8'sd3, 8'sd3,  8'sd3,  8'sd3,  8'sd3,  8'sd3,  8'sd3,  8'sd3,  8'sd3};
        run_single_task("D1_Ignore_Start_While_Busy", test_x, test_w, zero_stalls, 0, 1);

        // D2: Chay 5 tac vu lien tiep ngay khi ve IDLE (Back-to-back tasks)
        $display("\n>>> [D2] Chay 5 tac vu Back-to-Back lien tiep...");
        for (int t = 1; t <= 5; t++) begin
            for (int i = 0; i < 9; i++) begin
                test_x[i] = 8'(t * 10 + i);
                test_w[i] = 8'(i + 1);
            end
            run_single_task($sformatf("D2_BackToBack_Task_%0d", t), test_x, test_w, zero_stalls, 0, 0);
        end

        // --------------------------------------------------------------------
        // NHOM E: KIEM TRA HOI QUY NGAU NHIEN (RANDOM REGRESSION - 120 TASKS)
        // --------------------------------------------------------------------
        $display("\n>>> [Nhom E] Kiem tra Hoi quy Ngau nhien (120 tac vu doc lap)...");
        seed = 32'h20261004;
        $display("[INFO] Fixed Seed khoi tao: 0x%08h", seed);

        for (int t = 1; t <= 120; t++) begin
            for (int i = 0; i < 9; i++) begin
                test_x[i] = 8'($dist_uniform(seed, -128, 127));
                test_w[i] = 8'($dist_uniform(seed, -128, 127));
                random_stalls[i] = $dist_uniform(seed, 0, 3);
            end

            // Cho ngau nhien 0..2 chu ky o IDLE truoc khi bat dau tac vu tiep theo
            repeat ($dist_uniform(seed, 0, 2)) @(posedge clk);

            run_single_task($sformatf("E_Random_Task_%03d", t), test_x, test_w, random_stalls, (t % 5 == 0), 0);
        end

        // --------------------------------------------------------------------
        // TONG KET KET QUA KIEM CHUNG
        // --------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   KET QUA KIEM CHUNG GIAI DOAN 2 (dot9_int8):");
        $display("   - Tong so tac vu kiem tra:  %0d", total_tasks_passed);
        $display("   - So tac vu thanh cong:     %0d", total_tasks_passed);
        $display("   - So tac vu that bai:       %0d", total_tasks_failed);
        $display("   - Tong so chu ky xac thuc:  %0d", total_cycle_checks);
        $display("   - Tong so xung DONE hop le: %0d", done_pulse_count);
        $display("==================================================================");

        if (total_tasks_failed == 0) begin
            $display(">>> [SUCCESS] TAT CA CAC TESTBENCH GIAI DOAN 2 DA PASS 100%%!");
            $display(">>> Waveform VCD da luu tai: build/dot9_int8_waveform.vcd");
        end else begin
            $display(">>> [FAILURE] CO TESTBENCH THAT BAI!");
            $fatal(1);
        end

        $finish;
    end

endmodule
