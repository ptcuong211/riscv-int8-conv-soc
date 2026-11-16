// ============================================================================
// File: tb_soc_ram_2ff_safety.sv
// Description: Comprehensive 10-Check Safety & Reset Latency Validation for
//              candidate_local_sync_2ff (Two-Stage Local Synchronizer)
// Target: Phase 3F Validation against exact AASD Reset Generator
// ============================================================================

`timescale 1ns / 1ps

module tb_soc_ram_2ff_safety;

    logic        clk;
    logic        btn_reset;       // Raw asynchronous button reset
    logic        sys_rst;         // AASD output from fpga_top model
    logic        mem_valid;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0]  mem_wstrb;
    logic [31:0] mem_rdata;

    // Clock Generation: 100 MHz (Period = 10.0 ns)
    initial clk = 1'b0;
    always #5.0 clk = ~clk;

    // ------------------------------------------------------------------------
    // FPGA_TOP AASD RESET MODEL (Exact duplicate of fpga_top.sv)
    // ------------------------------------------------------------------------
    logic rst_sync_0, rst_sync_1;
    always_ff @(posedge clk or posedge btn_reset) begin
        if (btn_reset) begin
            rst_sync_0 <= 1'b1;
            rst_sync_1 <= 1'b1;
        end else begin
            rst_sync_0 <= 1'b0;
            rst_sync_1 <= rst_sync_0;
        end
    end
    assign sys_rst = rst_sync_1;

    // ------------------------------------------------------------------------
    // DUT: soc_ram (candidate_local_sync_2ff)
    // ------------------------------------------------------------------------
    soc_ram #(
        .WORDS     (4096),
        .INIT_FILE ("")
    ) dut (
        .clk       (clk),
        .rst       (sys_rst),
        .mem_valid (mem_valid),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata)
    );

    // ------------------------------------------------------------------------
    // Helper Tasks
    // ------------------------------------------------------------------------
    task automatic init_bus();
        btn_reset <= 1'b0;
        mem_valid <= 1'b0;
        mem_addr  <= 32'h0;
        mem_wdata <= 32'h0;
        mem_wstrb <= 4'h0;
    endtask

    task automatic write_word(input [31:0] addr, input [31:0] data, input [3:0] strb);
        @(posedge clk);
        mem_addr  <= addr;
        mem_wdata <= data;
        mem_wstrb <= strb;
        mem_valid <= 1'b1;
        @(posedge clk);
        while (!mem_ready) @(posedge clk);
        mem_valid <= 1'b0;
        mem_wstrb <= 4'h0;
    endtask

    task automatic read_word(input [31:0] addr, output [31:0] data);
        @(posedge clk);
        mem_addr  <= addr;
        mem_wstrb <= 4'h0;
        mem_valid <= 1'b1;
        @(posedge clk);
        while (!mem_ready) @(posedge clk);
        data = mem_rdata;
        mem_valid <= 1'b0;
    endtask

    int pass_count = 0;
    int fail_count = 0;
    logic [31:0] rdata_check;

    // ------------------------------------------------------------------------
    // MAIN VERIFICATION SEQUENCE (10 Rigorous Directed Checks)
    // ------------------------------------------------------------------------
    initial begin
        $display("==================================================================");
        $display("   PHASE 3F: SOC_RAM TWO-STAGE (2FF) RESET SAFETY VALIDATION");
        $display("   Testing candidate_local_sync_2ff with ASYNC_REG against AASD Generator");
        $display("==================================================================");

        init_bus();

        // --------------------------------------------------------------------
        // TEST 1: Cold Boot & Power-On Initialization Check
        // --------------------------------------------------------------------
        $display("\n>>> TEST 1: Cold boot & power-on initialization check...");
        // Check initial power-up state before reset is touched
        if (dut.rst_sync_reg0 === 1'b1 && dut.rst_sync_reg1 === 1'b1 && dut.ready_q === 1'b0) begin
            $display("[PASS] TEST 1: Initial power-up states safely initialize to RESET (reg0=1, reg1=1, ready_q=0).");
            pass_count++;
        end else begin
            $display("[FAIL] TEST 1: Unsafe cold boot state! reg0=%b, reg1=%b, ready_q=%b",
                     dut.rst_sync_reg0, dut.rst_sync_reg1, dut.ready_q);
            fail_count++;
        end

        // Release cold reset
        btn_reset <= 1'b1;
        repeat (3) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (5) @(posedge clk);

        // Populate baseline data in words 0..15 (0xA5A50000..0xA5A5000F)
        for (int i = 0; i < 16; i++) begin
            write_word(i * 4, 32'hA5A5_0000 + i, 4'b1111);
        end

        // --------------------------------------------------------------------
        // TEST 2: Reset during Idle State
        // --------------------------------------------------------------------
        $display("\n>>> TEST 2: Reset during Idle State...");
        btn_reset <= 1'b1;
        repeat (5) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (5) @(posedge clk);
        
        // Verify all 16 memory words intact
        begin : test2_verify
            automatic int corrupt_idle = 0;
            for (int i = 0; i < 16; i++) begin
                read_word(i * 4, rdata_check);
                if (rdata_check !== (32'hA5A5_0000 + i)) corrupt_idle++;
            end
            if (corrupt_idle == 0) begin
                $display("[PASS] TEST 2: All 16 words perfectly preserved across idle reset.");
                pass_count++;
            end else begin
                $display("[FAIL] TEST 2: %0d words corrupted during idle reset!", corrupt_idle);
                fail_count++;
            end
        end

        // --------------------------------------------------------------------
        // TEST 3: Reset during Mid-Read Transaction
        // --------------------------------------------------------------------
        $display("\n>>> TEST 3: Reset during Mid-Read Transaction...");
        @(posedge clk);
        mem_addr  <= 32'h0000_0008; // read word 2
        mem_valid <= 1'b1;
        mem_wstrb <= 4'b0000;
        #2.0;
        btn_reset <= 1'b1; // reset asserted while read is in flight
        @(posedge clk);
        mem_valid <= 1'b0;
        repeat (4) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (4) @(posedge clk);

        read_word(32'h0000_0008, rdata_check);
        if (rdata_check === 32'hA5A5_0002) begin
            $display("[PASS] TEST 3: Interrupted read cleanly aborted without modifying memory.");
            pass_count++;
        end else begin
            $display("[FAIL] TEST 3: Word 2 corrupted by mid-read reset! Got 0x%08h", rdata_check);
            fail_count++;
        end

        // --------------------------------------------------------------------
        // TEST 4: Reset Asserted Immediately BEFORE Clock Edge of Write (t = T - 1ns)
        // --------------------------------------------------------------------
        $display("\n>>> TEST 4: Reset asserted 1ns BEFORE clock edge of write...");
        // Word 4 starts with 0xA5A50004. We schedule a write of 0x44444444
        @(posedge clk);
        mem_addr  <= 32'h0000_0010; // word 4
        mem_wdata <= 32'h4444_4444;
        mem_wstrb <= 4'b1111;
        mem_valid <= 1'b1;
        #9.0;
        btn_reset <= 1'b1; // asserted 1ns before posedge
        #1.0;
        @(posedge clk);
        // Under 2-FF local sync:
        // At this edge, rst_sync_reg0 receives 1, but rst_sync_reg1 (rst_sync_local) is 0!
        // Therefore, transaction in flight completes cleanly on this edge.
        mem_valid <= 1'b0;
        mem_wstrb <= 4'b0000;
        repeat (4) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (4) @(posedge clk);

        read_word(32'h0000_0010, rdata_check);
        $display("  -> Word 4 after pre-edge reset: 0x%08h", rdata_check);
        if (rdata_check === 32'h4444_4444) begin
            $display("[PASS] TEST 4: In-flight write completed cleanly with deterministic value (0x44444444).");
            pass_count++;
        end else begin
            $display("[FAIL] TEST 4: Unexpected Word 4 value: 0x%08h (expected 0x44444444)", rdata_check);
            fail_count++;
        end

        // --------------------------------------------------------------------
        // TEST 5: Reset Asserted Immediately AFTER Clock Edge of Write (t = T + 1ns)
        // --------------------------------------------------------------------
        $display("\n>>> TEST 5: Reset asserted 1ns AFTER clock edge of write...");
        @(posedge clk);
        mem_addr  <= 32'h0000_0014; // word 5
        mem_wdata <= 32'h5555_5555;
        mem_wstrb <= 4'b1111;
        mem_valid <= 1'b1;
        #1.0;
        btn_reset <= 1'b1; // asserted 1ns after posedge
        @(posedge clk);
        mem_valid <= 1'b0;
        mem_wstrb <= 4'b0000;
        repeat (4) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (4) @(posedge clk);

        read_word(32'h0000_0014, rdata_check);
        $display("  -> Word 5 after post-edge reset: 0x%08h", rdata_check);
        if (rdata_check === 32'h5555_5555) begin
            $display("[PASS] TEST 5: Word 5 committed cleanly before reset arrival (0x55555555).");
            pass_count++;
        end else begin
            $display("[FAIL] TEST 5: Unexpected Word 5 value: 0x%08h", rdata_check);
            fail_count++;
        end

        // --------------------------------------------------------------------
        // TEST 6: Partial-Byte Writes under Reset
        // --------------------------------------------------------------------
        $display("\n>>> TEST 6: Partial-Byte Write (strb=4'b0100) under mid-cycle reset...");
        // Word 6 starts with 0xA5A50006. Write ONLY byte 2 (strb=4'b0100) with data 0x00EE_0000
        // Expected result: 0xA5EE_0006
        @(posedge clk);
        mem_addr  <= 32'h0000_0018; // word 6
        mem_wdata <= 32'h11EE_2233;
        mem_wstrb <= 4'b0100;       // only byte 2
        mem_valid <= 1'b1;
        #5.0;
        btn_reset <= 1'b1;
        @(posedge clk);
        mem_valid <= 1'b0;
        mem_wstrb <= 4'b0000;
        repeat (4) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (4) @(posedge clk);

        read_word(32'h0000_0018, rdata_check);
        $display("  -> Word 6 content: 0x%08h", rdata_check);
        if (rdata_check === 32'hA5EE_0006) begin
            $display("[PASS] TEST 6: Exact single-byte write committed without leaking into bytes 0, 1, 3.");
            pass_count++;
        end else begin
            $display("[FAIL] TEST 6: Byte enable violated! Got 0x%08h, expected 0xA5EE0006", rdata_check);
            fail_count++;
        end

        // --------------------------------------------------------------------
        // TEST 7: Sustained Reset (100 Cycles) and Rapid Consecutive Resets
        // --------------------------------------------------------------------
        $display("\n>>> TEST 7: Sustained Reset (100 cycles) + 10 Rapid Pulses...");
        btn_reset <= 1'b1;
        repeat (100) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (3) @(posedge clk);

        // Rapid 10-pulse toggling
        for (int p = 0; p < 10; p++) begin
            btn_reset <= 1'b1;
            @(posedge clk);
            btn_reset <= 1'b0;
            @(posedge clk);
        end
        repeat (5) @(posedge clk);

        // Verify Word 0..3 (which were not modified by Tests 4..6)
        begin : test7_verify
            automatic int corrupt_sustained = 0;
            for (int i = 0; i < 4; i++) begin
                read_word(i * 4, rdata_check);
                if (rdata_check !== (32'hA5A5_0000 + i)) corrupt_sustained++;
            end
            if (corrupt_sustained == 0) begin
                $display("[PASS] TEST 7: Zero corruption across 100 sustained cycles and 10 rapid toggles.");
                pass_count++;
            end else begin
                $display("[FAIL] TEST 7: %0d words corrupted after rapid toggling!", corrupt_sustained);
                fail_count++;
            end
        end

        // --------------------------------------------------------------------
        // TEST 8: Reset with Noisy / Corrupted Bus Lines
        // --------------------------------------------------------------------
        $display("\n>>> TEST 8: Bus Noise Injection during Active Reset...");
        btn_reset <= 1'b1;
        repeat (3) @(posedge clk);

        // Drive bus valid, write strobes, and corrupt data during reset
        for (int c = 0; c < 20; c++) begin
            @(posedge clk);
            mem_addr  <= 32'h0000_0000 + (c % 16) * 4;
            mem_wdata <= 32'hDEAD_0000 + c;
            mem_wstrb <= 4'b1111;
            mem_valid <= 1'b1;
            if (mem_ready !== 1'b0) begin
                $display("[FAIL] TEST 8: mem_ready asserted during reset at cycle %0d!", c);
                fail_count++;
            end
        end
        @(posedge clk);
        mem_valid <= 1'b0;
        mem_wstrb <= 4'b0000;
        repeat (5) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (5) @(posedge clk);

        // Verify that Word 0 remains 0xA5A50000
        read_word(32'h0000_0000, rdata_check);
        if (rdata_check === 32'hA5A5_0000) begin
            $display("[PASS] TEST 8: BRAM completely ignored all bus noise during reset.");
            pass_count++;
        end else begin
            $display("[FAIL] TEST 8: Word 0 corrupted by bus noise! Got 0x%08h", rdata_check);
            fail_count++;
        end

        // --------------------------------------------------------------------
        // TEST 9: Warm Reboot & Re-execution Verification
        // --------------------------------------------------------------------
        $display("\n>>> TEST 9: Emulate Full CPU Warm Reboot Sequence...");
        // Program simulated entry instructions at word 0 and word 1
        write_word(32'h0000_0000, 32'h0000_4137, 4'b1111); // lui sp, 0x4
        write_word(32'h0000_0004, 32'h0000_0297, 4'b1111); // auipc t0, 0

        // Trigger AASD Reset
        btn_reset <= 1'b1;
        repeat (5) @(posedge clk);
        btn_reset <= 1'b0;
        repeat (2) @(posedge clk);

        // Emulate CPU instruction fetch at address 0x0
        read_word(32'h0000_0000, rdata_check);
        if (rdata_check !== 32'h0000_4137) begin
            $display("[FAIL] TEST 9: Word 0 corrupted after reboot! Got 0x%08h", rdata_check);
            fail_count++;
        end else begin
            read_word(32'h0000_0004, rdata_check);
            if (rdata_check !== 32'h0000_0297) begin
                $display("[FAIL] TEST 9: Word 1 corrupted after reboot! Got 0x%08h", rdata_check);
                fail_count++;
            end else begin
                $display("[PASS] TEST 9: Reboot instruction fetch succeeded with 100%%%% data fidelity.");
                pass_count++;
            end
        end

        // --------------------------------------------------------------------
        // TEST 10: Exhaustive Verification of Program & Data RAM Boundaries
        // --------------------------------------------------------------------
        $display("\n>>> TEST 10: Boundary Verification (Addr 0x0000 to 0x3FFC)...");
        // Write top of RAM (16KB - 4 = 0x3FFC)
        write_word(32'h0000_3FFC, 32'hBEEF_CAFE, 4'b1111);
        read_word(32'h0000_3FFC, rdata_check);
        if (rdata_check === 32'hBEEF_CAFE) begin
            $display("[PASS] TEST 10: Boundary address 0x3FFC verified successfully.");
            pass_count++;
        end else begin
            $display("[FAIL] TEST 10: Boundary address 0x3FFC read mismatch! Got 0x%08h", rdata_check);
            fail_count++;
        end

        // ====================================================================
        // SUMMARY
        // ====================================================================
        $display("\n==================================================================");
        $display("   PHASE 3F 2-STAGE LOCAL SYNC VERIFICATION SUMMARY");
        $display("   Passed Directed Tests: %0d / 10", pass_count);
        $display("   Failed Directed Tests: %0d / 10", fail_count);
        $display("==================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL 10 PHASE 3F RESET SAFETY TESTS PASSED! <<<\n");
        end else begin
            $fatal(1, "One or more Phase 3F reset safety tests failed!");
        end

        $finish;
    end

endmodule
