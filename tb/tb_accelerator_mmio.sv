// ============================================================================
// Module Name: tb_accelerator_mmio
// Description: Unit-Level Testbench for accelerator_mmio Module (Stage 6)
// Target:      PicoRV32 Native Memory Bus & Accelerator Control Registers
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module tb_accelerator_mmio;

    localparam int CLK_PERIOD = 10;

    logic        clk;
    logic        rst;

    // Bus PicoRV32
    logic        mmio_valid;
    logic        mmio_ready;
    logic [31:0] mmio_addr;
    logic [31:0] mmio_wdata;
    logic [3:0]  mmio_wstrb;
    logic [31:0] mmio_rdata;

    // Accelerator Control
    logic        accel_start;
    logic        accel_busy;
    logic        accel_done;

    // Input Buffer Port
    logic        ibuf_wr_en;
    logic [9:0]  ibuf_wr_addr;
    logic signed [7:0] ibuf_wr_data;

    // Weight Buffer Port
    logic        wbuf_wr_en;
    logic [3:0]  wbuf_wr_addr;
    logic signed [7:0] wbuf_wr_data;

    // Output Buffer Port
    logic [9:0]  obuf_rd_addr;
    logic signed [31:0] obuf_rd_data;

    int test_pass = 0;
    int test_fail = 0;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    accelerator_mmio u_dut (
        .clk          (clk),
        .rst          (rst),
        .mmio_valid   (mmio_valid),
        .mmio_ready   (mmio_ready),
        .mmio_addr    (mmio_addr),
        .mmio_wdata   (mmio_wdata),
        .mmio_wstrb   (mmio_wstrb),
        .mmio_rdata   (mmio_rdata),
        .accel_start  (accel_start),
        .accel_busy   (accel_busy),
        .accel_done   (accel_done),
        .ibuf_wr_en   (ibuf_wr_en),
        .ibuf_wr_addr (ibuf_wr_addr),
        .ibuf_wr_data (ibuf_wr_data),
        .wbuf_wr_en   (wbuf_wr_en),
        .wbuf_wr_addr (wbuf_wr_addr),
        .wbuf_wr_data (wbuf_wr_data),
        .obuf_rd_addr (obuf_rd_addr),
        .obuf_rd_data (obuf_rd_data)
    );

    // Task thuc hien ghi MMIO
    task automatic mmio_write(input [31:0] addr, input [31:0] data);
        @(posedge clk);
        mmio_valid <= 1'b1;
        mmio_addr  <= addr;
        mmio_wdata <= data;
        mmio_wstrb <= 4'hF;
        @(posedge clk);
        while (!mmio_ready) @(posedge clk);
        @(posedge clk);
        mmio_valid <= 1'b0;
        mmio_wstrb <= 4'h0;
    endtask

    // Task thuc hien doc MMIO
    task automatic mmio_read(input [31:0] addr, output [31:0] data);
        @(posedge clk);
        mmio_valid <= 1'b1;
        mmio_addr  <= addr;
        mmio_wstrb <= 4'h0;
        @(posedge clk);
        while (!mmio_ready) @(posedge clk);
        data = mmio_rdata;
        @(posedge clk);
        mmio_valid <= 1'b0;
    endtask

    initial begin
        logic [31:0] rdata;
        rst          = 1'b1;
        mmio_valid   = 1'b0;
        mmio_addr    = '0;
        mmio_wdata   = '0;
        mmio_wstrb   = '0;
        accel_busy   = 1'b0;
        accel_done   = 1'b0;
        obuf_rd_data = 32'sd999;

        #(CLK_PERIOD * 5);
        rst = 1'b0;
        #(CLK_PERIOD * 2);

        $display("==================================================================");
        $display("   BAT DAU KIEM THU ACCELERATOR_MMIO (UNIT TEST)");
        $display("==================================================================");

        // Test 1: Ghi va doc IBUF_ADDR
        mmio_write(32'h1000_0008, 32'd512);
        mmio_read(32'h1000_0008, rdata);
        if (rdata === 32'd512) begin
            $display("[PASS] Test 1: IBUF_ADDR read/write match (512)");
            test_pass++;
        end else begin
            $display("[FAIL] Test 1: IBUF_ADDR got %0d != exp 512", rdata);
            test_fail++;
        end

        // Test 2: Ghi IBUF_DATA tao xung ibuf_wr_en
        fork
            begin
                mmio_write(32'h1000_000C, 32'h25);
            end
            begin
                @(posedge ibuf_wr_en);
                if (ibuf_wr_addr === 10'd512 && ibuf_wr_data === 8'sd37) begin
                    $display("[PASS] Test 2: IBUF_DATA pulse & data match (addr=512, data=37)");
                    test_pass++;
                end else begin
                    $display("[FAIL] Test 2: IBUF_DATA mismatch");
                    test_fail++;
                end
            end
        join

        // Test 3: Ghi START tao accel_start pulse
        fork
            begin
                mmio_write(32'h1000_0000, 32'd1);
            end
            begin
                @(posedge accel_start);
                @(posedge clk);
                #1;
                if (accel_start === 1'b0) begin
                    $display("[PASS] Test 3: START pulse is exactly 1 clock cycle");
                    test_pass++;
                end else begin
                    $display("[FAIL] Test 3: START pulse duration error");
                    test_fail++;
                end
            end
        join

        // Test 4: Sticky DONE va STATUS register
        accel_busy <= 1'b1;
        @(posedge clk);
        mmio_read(32'h1000_0004, rdata);
        if (rdata[0] === 1'b1 && rdata[1] === 1'b0) begin
            $display("[PASS] Test 4.1: STATUS reflects busy=1, done=0");
            test_pass++;
        end else begin
            $display("[FAIL] Test 4.1: STATUS got %b", rdata[1:0]);
            test_fail++;
        end

        // Phat xung accel_done 1 chu ky
        @(posedge clk);
        accel_done <= 1'b1;
        accel_busy <= 1'b0;
        @(posedge clk);
        accel_done <= 1'b0;

        // Doc lai STATUS kiem tra sticky_done
        mmio_read(32'h1000_0004, rdata);
        if (rdata[0] === 1'b0 && rdata[1] === 1'b1) begin
            $display("[PASS] Test 4.2: STATUS reflects sticky_done=1, busy=0");
            test_pass++;
        end else begin
            $display("[FAIL] Test 4.2: STATUS got %b", rdata[1:0]);
            test_fail++;
        end

        // Clear cờ DONE qua W1C
        mmio_write(32'h1000_0004, 32'd2);
        mmio_read(32'h1000_0004, rdata);
        if (rdata[1] === 1'b0) begin
            $display("[PASS] Test 4.3: W1C successfully cleared sticky_done");
            test_pass++;
        end else begin
            $display("[FAIL] Test 4.3: sticky_done not cleared");
            test_fail++;
        end

        // Test 5: Doc OBUF_DATA
        obuf_rd_data <= 32'sd1234567;
        mmio_write(32'h1000_0018, 32'd100);
        mmio_read(32'h1000_001C, rdata);
        if (rdata === 32'd1234567 && obuf_rd_addr === 10'd100) begin
            $display("[PASS] Test 5: OBUF_ADDR & OBUF_DATA read match (1234567)");
            test_pass++;
        end else begin
            $display("[FAIL] Test 5: OBUF_DATA got %0d", rdata);
            test_fail++;
        end

        $display("==================================================================");
        $display("   KET QUA UNIT TEST MMIO: PASS=%0d, FAIL=%0d", test_pass, test_fail);
        $display("==================================================================");
        if (test_fail == 0) begin
            $display(">>> TAT CA CAC TESTBENCH ACCELERATOR_MMIO DA PASS 100%%! <<<");
        end
        $finish;
    end

endmodule

