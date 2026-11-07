// ============================================================================
// Module Name: tb_output_buffer
// Description: Comprehensive Self-Checking Testbench for output_buffer (Stage 5)
// Target:      RISC-V INT8 Convolution Accelerator
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module tb_output_buffer;

    // ------------------------------------------------------------------------
    // Thong so cau hinh
    // ------------------------------------------------------------------------
    localparam int DATA_WIDTH = 32;
    localparam int DEPTH      = 900;
    localparam int ADDR_WIDTH = 10;
    localparam int CLK_PERIOD = 10; // 100 MHz (10ns period)

    // ------------------------------------------------------------------------
    // Tin hieu ket noi DUT
    // ------------------------------------------------------------------------
    logic                          clk;
    logic                          wr_en;
    logic [ADDR_WIDTH-1:0]         wr_addr;
    logic signed [DATA_WIDTH-1:0]  wr_data;
    logic [ADDR_WIDTH-1:0]         rd_addr;
    logic signed [DATA_WIDTH-1:0]  rd_data;

    // Bien dem kiem chung
    int test_pass_count = 0;
    int test_fail_count = 0;

    // ------------------------------------------------------------------------
    // Tao xung clock 100 MHz
    // ------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Khoi tao DUT
    // ------------------------------------------------------------------------
    output_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .RAM_STYLE  ("block")
    ) u_dut (
        .clk     (clk),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    // ------------------------------------------------------------------------
    // Dump waveform
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("output_buffer_waveform.vcd");
        $dumpvars(0, tb_output_buffer);
    end

    // ------------------------------------------------------------------------
    // Task ghi du lieu 1 tu
    // ------------------------------------------------------------------------
    task automatic write_word(input [ADDR_WIDTH-1:0] addr, input signed [DATA_WIDTH-1:0] data);
        @(posedge clk);
        wr_en   <= 1'b1;
        wr_addr <= addr;
        wr_data <= data;
        @(posedge clk);
        wr_en   <= 1'b0;
        wr_addr <= '0;
        wr_data <= '0;
    endtask

    // ------------------------------------------------------------------------
    // Task doc va kiem tra 1 tu voi 1-cycle latency
    // ------------------------------------------------------------------------
    task automatic check_word(input [ADDR_WIDTH-1:0] addr, input signed [DATA_WIDTH-1:0] expected, input string tag);
        @(posedge clk);
        rd_addr <= addr;
        @(posedge clk); // Cho 1 chu ky latency de BRAM xuat du lieu
        #1; // Lay mau sau edge clock
        if (rd_data === expected) begin
            $display("[PASS] %s | Addr: %0d | Data: %0d (0x%08h)", tag, addr, rd_data, rd_data);
            test_pass_count++;
        end else begin
            $display("[FAIL] %s | Addr: %0d | Got: %0d (0x%08h) != Exp: %0d (0x%08h)",
                     tag, addr, rd_data, rd_data, expected, expected);
            test_fail_count++;
        end
    endtask

    // ------------------------------------------------------------------------
    // Chuong trinh kiem thu chinh
    // ------------------------------------------------------------------------
    initial begin
        $display("==================================================================");
        $display("   BAT DAU KIEM THU OUTPUT_BUFFER (STAGE 5)");
        $display("==================================================================");

        // Khoi tao tin hieu
        wr_en   = 1'b0;
        wr_addr = '0;
        wr_data = '0;
        rd_addr = '0;
        #(CLK_PERIOD * 2);

        // ====================================================================
        // TEST 1: Basic Write / Read
        // ====================================================================
        $display("\n>>> TEST 1: Basic Write / Read...");
        write_word(10'd5,  32'sd12345);
        write_word(10'd42, 32'sd98765);
        write_word(10'd100, -32'sd5555);

        check_word(10'd5,   32'sd12345, "TEST 1.1");
        check_word(10'd42,  32'sd98765, "TEST 1.2");
        check_word(10'd100, -32'sd5555, "TEST 1.3");

        // ====================================================================
        // TEST 2: Boundary Addresses (0 va 899)
        // ====================================================================
        $display("\n>>> TEST 2: Boundary Addresses (0 va 899)...");
        write_word(10'd0,   32'sd111111);
        write_word(10'd899, 32'sd999999);

        check_word(10'd0,   32'sd111111, "TEST 2.1 (Boundary Addr 0)");
        check_word(10'd899, 32'sd999999, "TEST 2.2 (Boundary Addr 899)");

        // ====================================================================
        // TEST 3: Signed INT32 Extreme Values
        // ====================================================================
        $display("\n>>> TEST 3: Signed INT32 Values (+, -, 0, MAX, MIN)...");
        write_word(10'd10, 32'sd0);
        write_word(10'd11, 32'sd1);
        write_word(10'd12, -32'sd1);
        write_word(10'd13, 32'sh7FFFFFFF); // +2,147,483,647 (Max signed 32-bit)
        write_word(10'd14, 32'sh80000000); // -2,147,483,648 (Min signed 32-bit)
        write_word(10'd15, -32'sd12345678);

        check_word(10'd10, 32'sd0,        "TEST 3.1 (Zero)");
        check_word(10'd11, 32'sd1,        "TEST 3.2 (+1)");
        check_word(10'd12, -32'sd1,       "TEST 3.3 (-1)");
        check_word(10'd13, 32'sh7FFFFFFF, "TEST 3.4 (MAX INT32)");
        check_word(10'd14, 32'sh80000000, "TEST 3.5 (MIN INT32)");
        check_word(10'd15, -32'sd12345678,"TEST 3.6 (Negative)");

        // ====================================================================
        // TEST 4: Sequential Write & Read All 900 Words
        // ====================================================================
        $display("\n>>> TEST 4: Sequential Write & Read All 900 Words (0..899)...");
        // Ghi 900 gia tri kieu pipeline: moi chu ky 1 gia tri
        @(posedge clk);
        for (int i = 0; i < DEPTH; i++) begin
            wr_en   <= 1'b1;
            wr_addr <= 10'(i);
            // Dữ liệu kiểm tra: đan xen số dương và âm
            wr_data <= signed'(32'((i * 101) - 45000));
            @(posedge clk);
        end
        wr_en   <= 1'b0;
        wr_addr <= '0;
        wr_data <= '0;
        @(posedge clk);

        // Doc lai kiem tra 900 phan tu (Pipelined Read)
        begin
            logic signed [DATA_WIDTH-1:0] expected_val;
            int seq_err_count = 0;

            // Thiet lap doc phan tu dau tien
            rd_addr <= 10'd0;
            @(posedge clk); // Sau posedge nay, mem[0] dang duoc doc

            for (int i = 0; i < DEPTH; i++) begin
                // Dat dia chi cho chu ky ke tiep
                if (i + 1 < DEPTH) begin
                    rd_addr <= 10'(i + 1);
                end
                #1; // Lay mau rd_data cua chu ky i
                expected_val = signed'(32'((i * 101) - 45000));
                if (rd_data !== expected_val) begin
                    $display("[FAIL] TEST 4 | Addr %0d | Got: %0d != Exp: %0d", i, rd_data, expected_val);
                    seq_err_count++;
                end
                @(posedge clk);
            end

            if (seq_err_count == 0) begin
                $display("[PASS] TEST 4: Toan bo 900/900 phan tu doc lai khop chinh xac 100%%!");
                test_pass_count++;
            end else begin
                $display("[FAIL] TEST 4: Co %0d / 900 phan tu doc bi sai!", seq_err_count);
                test_fail_count++;
            end
        end

        // ====================================================================
        // TEST 5: Verify 1-Cycle Read Latency
        // ====================================================================
        $display("\n>>> TEST 5: Verify Exact 1-Cycle Read Latency...");
        // Ghi gia tri tai dia chi 200 va 201
        write_word(10'd200, 32'shAAAA_0001);
        write_word(10'd201, 32'shBBBB_0002);

        // Chu ky T0: Dat rd_addr = 200
        @(posedge clk);
        rd_addr <= 10'd200;
        #1;
        // Tai chu ky T0, rd_data chua the la 0xAAAA_0001 vi can 1 chu ky latency
        if (rd_data === 32'shAAAA_0001) begin
            $display("[WARN] TEST 5 | Du lieu da ra ngay tai chu ky T0 (Asynchronous Read - khong phai 1-cycle BRAM)!");
        end

        // Chu ky T1: Sau 1 chu ky clock
        @(posedge clk);
        #1;
        if (rd_data === 32'shAAAA_0001) begin
            $display("[PASS] TEST 5.1: Tai chu ky T1 (sau dung 1 chu ky), rd_data = 0x%08h chinh xac!", rd_data);
            test_pass_count++;
        end else begin
            $display("[FAIL] TEST 5.1: Tai chu ky T1, rd_data = 0x%08h != Exp: 0xAAAA_0001", rd_data);
            test_fail_count++;
        end

        // Doi dia chi sang 201 tai chu ky T1
        rd_addr <= 10'd201;
        @(posedge clk); // Chu ky T2
        #1;
        if (rd_data === 32'shBBBB_0002) begin
            $display("[PASS] TEST 5.2: Tai chu ky T2, rd_data chuyen sang 0x%08h sau dung 1 chu ky!", rd_data);
            test_pass_count++;
        end else begin
            $display("[FAIL] TEST 5.2: Tai chu ky T2, rd_data = 0x%08h != Exp: 0xBBBB_0002", rd_data);
            test_fail_count++;
        end

        // ====================================================================
        // Tong ket kiem chung
        // ====================================================================
        $display("\n==================================================================");
        $display("   TONG KET KIEM CHUNG OUTPUT_BUFFER (STAGE 5)");
        $display("   So testcase PASS: %0d", test_pass_count);
        $display("   So testcase FAIL: %0d", test_fail_count);
        $display("==================================================================");

        if (test_fail_count == 0) begin
            $display(">>> TAT CA CAC TESTBENCH OUTPUT_BUFFER DA PASS 100%%! <<<");
        end else begin
            $display(">>> CO TESTBENCH OUTPUT_BUFFER BI THAT BAI! <<<");
        end

        $finish;
    end

endmodule

