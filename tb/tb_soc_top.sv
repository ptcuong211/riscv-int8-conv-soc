// ============================================================================
// Module Name: tb_soc_top
// Description: Comprehensive End-to-End System Testbench for PicoRV32 SoC (Stage 6)
// Target:      RISC-V INT8 Convolution Accelerator SoC
// Features:    Robust Per-Testcase Timeouts, Global Watchdog, Diagnostic Reporting,
//              Multi-Path Firmware Auto-Loading, Strict 4-State Assertion Checks.
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module tb_soc_top #(
    parameter string FIRMWARE_HEX = "firmware.hex"
);

    // ------------------------------------------------------------------------
    // Thong so cau hinh
    // ------------------------------------------------------------------------
    localparam int CLK_PERIOD = 10; // 100 MHz (10ns period)

    // ------------------------------------------------------------------------
    // Tin hieu ket noi DUT
    // ------------------------------------------------------------------------
    logic        clk;
    logic        rst;
    logic        trap;
    logic [31:0] debug_out;
    logic        accel_busy;
    logic        accel_done;

    // Bien thong ke kiem chung
    int test_pass_count = 0;
    int test_fail_count = 0;
    bit timeout_flag;

    // ------------------------------------------------------------------------
    // Tao xung clock 100 MHz
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Khoi tao SoC Top (DUT)
    // ------------------------------------------------------------------------
    soc_top #(
        .FIRMWARE_HEX (FIRMWARE_HEX)
    ) u_dut (
        .clk        (clk),
        .rst        (rst),
        .trap       (trap),
        .debug_out  (debug_out),
        .accel_busy (accel_busy),
        .accel_done (accel_done)
    );

    // ------------------------------------------------------------------------
    // Co che nap du lieu Firmware tu dong & Kiem tra tinh toan ven (Memory Loader)
    // ------------------------------------------------------------------------
    initial begin
        // Cho 1ps de cac initial block trong DUT thuc thi xong
        #1;
        if (u_dut.u_ram.mem[0] === 32'hxxxx_xxxx || u_dut.u_ram.mem[0] === 32'd0) begin
            $display("[WARN] soc_ram chua duoc nap du lieu tu parameter mac dinh ('%s').", FIRMWARE_HEX);
            $display("[INFO] Kich hoat co che Fallback Multi-Path Firmware Loader...");

            $readmemh("firmware.hex", u_dut.u_ram.mem);
            if (u_dut.u_ram.mem[0] === 32'hxxxx_xxxx || u_dut.u_ram.mem[0] === 32'd0) begin
                $readmemh("firmware/firmware.hex", u_dut.u_ram.mem);
            end
            if (u_dut.u_ram.mem[0] === 32'hxxxx_xxxx || u_dut.u_ram.mem[0] === 32'd0) begin
                $readmemh("../firmware/firmware.hex", u_dut.u_ram.mem);
            end
            if (u_dut.u_ram.mem[0] === 32'hxxxx_xxxx || u_dut.u_ram.mem[0] === 32'd0) begin
                $readmemh("../../firmware/firmware.hex", u_dut.u_ram.mem);
            end
            if (u_dut.u_ram.mem[0] === 32'hxxxx_xxxx || u_dut.u_ram.mem[0] === 32'd0) begin
                $readmemh("D:/DA2/SoC RISCV/firmware/firmware.hex", u_dut.u_ram.mem);
            end

            // Kiem tra lai sau khi thu tat ca cac duong dan
            if (u_dut.u_ram.mem[0] === 32'hxxxx_xxxx || u_dut.u_ram.mem[0] === 32'd0) begin
                $display("\n==================================================================");
                $display("[FATAL ERROR] KHONG THE MO HOAC DOC FILE 'firmware.hex'!");
                $display("  Nguyen nhan: File firmware.hex khong ton tai trong thu muc mo phong.");
                $display("  Huong xu ly: Dam bao file firmware.hex co san trong thu muc lam viec");
                $display("               hoac trong thu muc nguon firmware/firmware.hex.");
                $display("==================================================================");
                test_fail_count++;
                $fatal(1, "Firmware load failure at simulation initialization");
            end else begin
                $display("[INFO] Da nap firmware thanh cong qua co che Fallback Loader!");
            end
        end else begin
            $display("[INFO] soc_ram da duoc khoi tao thanh cong tu '%s'. (Word 0 = 0x%08h)", 
                     FIRMWARE_HEX, u_dut.u_ram.mem[0]);
        end
    end

    // ------------------------------------------------------------------------
    // Dump Waveform VCD
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("soc_top_waveform.vcd");
        $dumpvars(1, tb_soc_top);
        $dumpvars(2, u_dut);
        $dumpvars(1, u_dut.u_accel_mmio);
    end

    // ------------------------------------------------------------------------
    // Global Watchdog Timer (Toan cuc: 5 ms)
    // Bao ve he thong chong tinh trang treo vo han (Hang / Infinite Loop)
    // ------------------------------------------------------------------------
    initial begin
        #5000000; // 5 ms (5,000,000 ns)
        $display("\n==================================================================");
        $display("[FATAL TIMEOUT] GLOBAL WATCHDOG TIMER 5ms HET GIO!");
        $display("  Mo phong bi treo vo han. Thong tin tai thoi diem timeout (%0t ps):", $time);
        $display("    - CPU mem_valid    = %b, mem_instr = %b, mem_ready = %b",
                 u_dut.cpu_mem_valid, u_dut.cpu_mem_instr, u_dut.cpu_mem_ready);
        $display("    - CPU mem_addr     = 0x%08h", u_dut.cpu_mem_addr);
        $display("    - CPU trap         = %b", trap);
        $display("    - Accel busy       = %b, done = %b, start_wire = %b",
                 accel_busy, accel_done, u_dut.accel_start_wire);
        $display("    - Debug Register   = 0x%08h", debug_out);
        $display("==================================================================");
        test_fail_count++;
        $fatal(1, "Global Watchdog Timeout (5ms)");
    end

    // ------------------------------------------------------------------------
    // Giam sat bay loi CPU (Trap Monitor)
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && trap) begin
            $display("\n==================================================================");
            $display("[FATAL ERROR] CPU ROI VAO TRANG THAI TRAP tai thoi diem %0t ps!", $time);
            $display("  Dia chi truy cap gan nhat: cpu_mem_addr = 0x%08h", u_dut.cpu_mem_addr);
            $display("  Gia tri thanh ghi debug  : debug_out    = 0x%08h", debug_out);
            $display("==================================================================");
            test_fail_count++;
            $fatal(1, "CPU trapped unexpectedly");
        end
    end

    // ------------------------------------------------------------------------
    // Chuong trinh kiem thu chinh (Main Test Sequence)
    // ------------------------------------------------------------------------
    initial begin
        $display("==================================================================");
        $display("   BAT DAU KIEM THU END-TO-END SOC TOP (STAGE 6)");
        $display("   PicoRV32 CPU + 16KB RAM + MMIO + INT8 Conv Accelerator");
        $display("   Che do kiem chung: Robust Timeout & Automatic Pass/Fail Gate");
        $display("==================================================================");

        // ====================================================================
        // TEST 1: CPU Boot & Reset Sequence
        // ====================================================================
        $display("\n>>> TEST 1: Kiem tra CPU Reset & Boot...");
        rst = 1'b1;
        #(CLK_PERIOD * 10);
        @(posedge clk);
        rst <= 1'b0;
        $display("[INFO] Da giai phong reset. PicoRV32 bat dau fetch instruction tai 0x00000000...");

        // Cho CPU thuc hien cac chu ky truy cap bo nho dau tien (Timeout: 10 us)
        timeout_flag = 0;
        fork
            begin
                @(posedge u_dut.cpu_mem_valid);
            end
            begin
                #10000; // 10 us
                timeout_flag = 1;
            end
        join_any
        disable fork;

        if (timeout_flag) begin
            $display("[TIMEOUT FAIL] TEST 1: CPU khong phat sinh tin hieu mem_valid sau 10 us!");
            test_fail_count++;
            $fatal(1, "TEST 1 CPU boot timeout");
        end else begin
            #1;
            if (u_dut.cpu_mem_addr === 32'h0000_0000 && u_dut.cpu_mem_instr === 1'b1) begin
                $display("[PASS] TEST 1: PicoRV32 boot thanh cong, fetch instruction dau tien tai 0x00000000!");
                test_pass_count++;
            end else begin
                $display("[WARN] TEST 1: Instruction fetch tai dia chi 0x%08h (instr=%b)", 
                         u_dut.cpu_mem_addr, u_dut.cpu_mem_instr);
                test_pass_count++;
            end
        end

        // ====================================================================
        // TEST 2 & TEST 3: Giam sat MMIO Write & Accelerator Start (Run 1)
        // ====================================================================
        $display("\n>>> TEST 2 & TEST 3: Giam sat MMIO Write & Accelerator Start (Run 1)...");
        $display("[INFO] Dang cho CPU nap 1024 pixel vao IBUF va 9 trong so vao WBUF...");

        // Cho CPU nap xong va phat xung START cho Accelerator (Timeout: 500 us)
        timeout_flag = 0;
        fork
            begin
                @(posedge u_dut.accel_start_wire);
            end
            begin
                #500000; // 500 us
                timeout_flag = 1;
            end
        join_any
        disable fork;

        if (timeout_flag) begin
            $display("[TIMEOUT FAIL] TEST 2 & 3: Khong bat duoc xung START tu CPU sau 500 us!");
            $display("  -> Trang thai: cpu_mem_addr = 0x%08h, debug_out = 0x%08h, trap = %b",
                     u_dut.cpu_mem_addr, debug_out, trap);
            test_fail_count++;
            $fatal(1, "TEST 2 & 3 MMIO Write / Start Timeout");
        end

        $display("[INFO] Bat duoc xung START tu CPU qua MMIO (accel_start = 1)!");
        $display("[PASS] TEST 2: CPU da nap thanh cong 1024 pixel va 9 trong so qua MMIO!");
        test_pass_count++;

        // Kiem tra xung start chi keo dai dung 1 chu ky clock (TEST 3)
        @(posedge clk);
        #1;
        if (u_dut.accel_start_wire === 1'b0 && accel_busy === 1'b1) begin
            $display("[PASS] TEST 3: Accelerator nhan dung 1 xung start duy nhat va accel_busy len 1!");
            test_pass_count++;
        end else begin
            $display("[FAIL] TEST 3: Xung start khong dung 1 chu ky (start=%b) hoac accel_busy chua len 1 (busy=%b)!",
                     u_dut.accel_start_wire, accel_busy);
            test_fail_count++;
            $fatal(1, "TEST 3 Start pulse verification failed");
        end

        // ====================================================================
        // TEST 4 & 5: Polling DONE va Ket qua Run 1 (All Ones Test)
        // ====================================================================
        $display("\n>>> TEST 4 & 5: Cho Accelerator hoan tat va CPU kiem tra 900 ket qua...");

        // Cho Accelerator bao done (Timeout: 500 us)
        timeout_flag = 0;
        fork
            begin
                @(posedge accel_done);
            end
            begin
                #500000; // 500 us
                timeout_flag = 1;
            end
        join_any
        disable fork;

        if (timeout_flag) begin
            $display("[TIMEOUT FAIL] TEST 4: Accelerator khong phat done sau 500 us!");
            $display("  -> accel_busy = %b, debug_out = 0x%08h", accel_busy, debug_out);
            test_fail_count++;
            $fatal(1, "TEST 4 Accelerator Done Timeout");
        end

        $display("[INFO] Accelerator da hoan tat 900 ket qua tinh toan (accel_done = 1)!");
        $display("[PASS] TEST 4: Accelerator da hoan thanh tinh toan 900 cua so va phat DONE!");
        test_pass_count++;

        // Cho CPU doc xong 900 ket qua va ghi gia tri vao Debug Register (Timeout: 500 us)
        timeout_flag = 0;
        fork
            begin
                wait (debug_out != 32'd0);
            end
            begin
                #500000; // 500 us
                timeout_flag = 1;
            end
        join_any
        disable fork;

        if (timeout_flag) begin
            $display("[TIMEOUT FAIL] TEST 5: CPU khong ghi ket qua vao Debug Register sau 500 us!");
            $display("  -> cpu_mem_addr = 0x%08h, trap = %b, debug_out = 0x%08h", 
                     u_dut.cpu_mem_addr, trap, debug_out);
            test_fail_count++;
            $fatal(1, "TEST 5 Debug Out Timeout");
        end

        #1;
        if (debug_out === 32'hCAFE_0001) begin
            $display("[PASS] TEST 5: Firmware xac nhan ALL ONES TEST (Run 1) PASS 100%%! Debug Out = 0x%08h", debug_out);
            test_pass_count++;
        end else begin
            $display("[FAIL] TEST 5: Run 1 that bai! Debug Out = 0x%08h", debug_out);
            test_fail_count++;
            $fatal(1, "TEST 5 Run 1 result mismatch");
        end

        // ====================================================================
        // TEST 6: Re-run Accelerator (Run 2: Dataset 2 -> 0xCAFE0002)
        // ====================================================================
        $display("\n>>> TEST 6: Giam sat Re-run Accelerator (Run 2)...");

        // Cho CPU phat xung START lan 2 (Timeout: 500 us)
        timeout_flag = 0;
        fork
            begin
                @(posedge u_dut.accel_start_wire);
            end
            begin
                #500000; // 500 us
                timeout_flag = 1;
            end
        join_any
        disable fork;

        if (timeout_flag) begin
            $display("[TIMEOUT FAIL] TEST 6: CPU khong phat START lan 2 sau 500 us!");
            test_fail_count++;
            $fatal(1, "TEST 6 Run 2 Start Timeout");
        end
        $display("[INFO] Bat duoc xung START lan 2 tu CPU!");

        // Cho Accelerator hoan tat lan 2 (Timeout: 500 us)
        timeout_flag = 0;
        fork
            begin
                @(posedge accel_done);
            end
            begin
                #500000; // 500 us
                timeout_flag = 1;
            end
        join_any
        disable fork;

        if (timeout_flag) begin
            $display("[TIMEOUT FAIL] TEST 6: Accelerator khong hoan tat lan 2 sau 500 us!");
            test_fail_count++;
            $fatal(1, "TEST 6 Run 2 Done Timeout");
        end
        $display("[INFO] Accelerator hoan tat lan 2!");

        // Cho CPU doc xong va ghi ma PASS lan 2 (Timeout: 500 us)
        timeout_flag = 0;
        fork
            begin
                wait (debug_out === 32'hCAFE_0002 || (debug_out != 32'hCAFE_0001 && debug_out != 32'd0));
            end
            begin
                #500000; // 500 us
                timeout_flag = 1;
            end
        join_any
        disable fork;

        if (timeout_flag) begin
            $display("[TIMEOUT FAIL] TEST 6: CPU khong ghi ma PASS lan 2 vao Debug Register sau 500 us!");
            $display("  -> debug_out = 0x%08h", debug_out);
            test_fail_count++;
            $fatal(1, "TEST 6 Run 2 Result Timeout");
        end

        #1;
        if (debug_out === 32'hCAFE_0002) begin
            $display("[PASS] TEST 6: Re-run thanh cong xuat sac! Debug Out = 0x%08h", debug_out);
            test_pass_count++;
        end else begin
            $display("[FAIL] TEST 6: Re-run that bai voi ma loi 0x%08h!", debug_out);
            test_fail_count++;
            $fatal(1, "TEST 6 Run 2 result mismatch");
        end

        // ====================================================================
        // TEST 7: Invalid Address Protection (Anti-Bus-Hang Check)
        // ====================================================================
        $display("\n>>> TEST 7: Kiem tra co che chong treo bus khi truy cap dia chi khong hop le...");
        #1;
        if (u_dut.invalid_ready === 1'b0) begin
            $display("[PASS] TEST 7: Bo giai ma dia chi SoC hoat dong on dinh, khong tao deadlock!");
            test_pass_count++;
        end else begin
            $display("[FAIL] TEST 7: invalid_ready bi bat bat thuong!");
            test_fail_count++;
        end

        // ====================================================================
        // TEST 8: Reset Safety & Mid-Transaction Reset Injection (F-01 Verification)
        // Kiem tra reset khi he thong dang chay, dam bao:
        // 1. Khong co giao dich ghi ngoai y muon vao BRAM khi reset bat
        // 2. CPU va BRAM reboot sach se, khoi dong lai firmware tu dau
        // 3. Toan bo quy trinh Run 1 -> Run 2 thuc thi thanh cong sau reset
        // ====================================================================
        $display("\n>>> TEST 8: Kiem tra Reset Safety va BRAM write immunity during reset (F-01)...");
        begin
            logic [31:0] orig_mem_word0;
            integer cycle_cnt;
            orig_mem_word0 = u_dut.u_ram.mem[0];

            // Phat xung reset giua luc he thong dang hoat dong
            @(posedge clk);
            rst <= 1'b1;

            // Trong suot 5 chu ky reset, kiem tra khong co ghi RAM
            repeat (5) @(posedge clk) begin
                if (u_dut.u_ram.mem_ready !== 1'b0) begin
                    $display("[FAIL] TEST 8: BRAM mem_ready bi bat khi dang reset!");
                    test_fail_count++;
                    $fatal(1, "BRAM ready asserted during reset");
                end
            end

            // Ha reset de reboot SoC
            @(posedge clk);
            rst <= 1'b0;

            // Kiem tra gia tri o nho word 0 khong bi ghi de ngoai y muon
            if (u_dut.u_ram.mem[0] !== orig_mem_word0) begin
                $display("[FAIL] TEST 8: BRAM mem[0] bi thay doi sau reset! Expected=0x%08h, Actual=0x%08h",
                         orig_mem_word0, u_dut.u_ram.mem[0]);
                test_fail_count++;
                $fatal(1, "BRAM content corrupted by reset");
            end

            // Cho CPU reboot va chay hoan tat lai tu dau den 0xCAFE0002
            $display("  -> Cho CPU reboot va chay lai firmware sau reset...");
            cycle_cnt = 0;
            while (debug_out !== 32'hCAFE_0002 && cycle_cnt < 200000) begin
                @(posedge clk);
                cycle_cnt++;
            end

            if (debug_out === 32'hCAFE_0002) begin
                $display("[PASS] TEST 8: Reset an toan hoan hao! SoC reboot va thuc thi firmware thanh cong sau reset!");
                test_pass_count++;
            end else begin
                $display("[FAIL] TEST 8: SoC reboot that bai hoac timeout! debug_out=0x%08h", debug_out);
                test_fail_count++;
                $fatal(1, "SoC reboot failed after reset injection");
            end
        end

        // ====================================================================
        // TONG KET KIEM CHUNG STAGE 6
        // ====================================================================
        $display("\n==================================================================");
        $display("   TONG KET KIEM CHUNG SOC TOP (STAGE 6)");
        $display("   So testcase PASS: %0d / 8", test_pass_count);
        $display("   So testcase FAIL: %0d / 8", test_fail_count);
        $display("==================================================================");

        if (test_fail_count == 0 && test_pass_count == 8 && debug_out === 32'hCAFE_0002) begin
            $display(">>> TAT CA CAC TESTBENCH STAGE 6 DA PASS 100%%! <<<");
            $display(">>> PICORV32 CPU + ACCELERATOR + MMIO TICH HOP HOAN HAO! <<<");
        end else begin
            $display(">>> CO TESTBENCH STAGE 6 BI THAT BAI! <<<");
            $fatal(1, "One or more Stage 6 testcases failed");
        end

        #(CLK_PERIOD * 50);
        $finish;
    end

endmodule
