// ============================================================================
// Module Name: tb_fpga_top_uart
// Description: End-to-End Testbench for fpga_top with UART Serial RX Decoder
//              Decodes 115200 Baud 8N1 serial data from uart_tx_out pin
// ============================================================================

`timescale 1ns / 1ps

module tb_fpga_top_uart;

    logic        clk_100mhz;
    logic        btn_reset;
    logic [15:0] led;
    logic        uart_tx_out;

    // Clock generation: 100 MHz (10ns period)
    initial clk_100mhz = 1'b0;
    always #5 clk_100mhz = ~clk_100mhz;

    // DUT Instantiation
    fpga_top #(
        .FIRMWARE_HEX("firmware.hex")
    ) dut (
        .clk_100mhz (clk_100mhz),
        .btn_reset  (btn_reset),
        .led        (led),
        .uart_tx_out(uart_tx_out)
    );

    // ========================================================================
    // UART Software Receiver (115200 Baud, 8-N-1)
    // Bit period = 8680 ns (868 clock cycles of 10ns)
    // Half bit period = 4340 ns (434 clock cycles)
    // ========================================================================
    localparam time BIT_PERIOD = 8680ns;
    localparam time HALF_BIT_PERIOD = 4340ns;

    string received_chars = "";
    int byte_count = 0;
    logic rx_framing_error = 1'b0;

    task automatic uart_rx_byte(output logic [7:0] data, output logic err);
        logic [7:0] rx_byte;
        err = 1'b0;

        // Wait for falling edge of Start bit
        @(negedge uart_tx_out);
        #HALF_BIT_PERIOD; // sample in middle of Start bit
        if (uart_tx_out !== 1'b0) begin
            $display("[UART RX ERROR] False start bit detected at %t", $realtime);
            err = 1'b1;
            return;
        end

        // Sample 8 data bits (LSB first)
        for (int i = 0; i < 8; i++) begin
            #BIT_PERIOD;
            rx_byte[i] = uart_tx_out;
        end

        // Sample Stop bit
        #BIT_PERIOD;
        if (uart_tx_out !== 1'b1) begin
            $display("[UART RX ERROR] Framing error: Stop bit not 1 at %t (got %b)", $realtime, uart_tx_out);
            err = 1'b1;
            rx_framing_error = 1'b1;
        end

        data = rx_byte;
    endtask

    // Background thread: continuously capture received bytes
    initial begin
        logic [7:0] rx_data;
        logic       err;
        forever begin
            uart_rx_byte(rx_data, err);
            if (!err) begin
                byte_count++;
                received_chars = {received_chars, string'(rx_data)};
                $write("%c", rx_data);
            end
        end
    end

    // Test sequence
    initial begin
        $display("==================================================================");
        $display("  STARTING FPGA_TOP UART END-TO-END VERIFICATION");
        $display("==================================================================");

        btn_reset = 1'b1;
        #100ns;
        @(posedge clk_100mhz);
        btn_reset = 1'b0;
        $display("[%t] Reset deasserted, SoC running...", $realtime);

        // Run until CPU completes Run 2 (led[15] == 1)
        wait (led[15] == 1'b1);
        $display("\n[%t] CPU finished RUN 2! led[15]=1 (debug_out=0xCAFE0002)", $realtime);

        // Wait up to 6ms for UART to finish transmitting all 57 bytes (57 * 86.8us ~ 4.95ms)
        #6ms;

        $display("\n==================================================================");
        $display("  UART RECEPTION SUMMARY");
        $display("  Total Bytes Received: %0d", byte_count);
        $display("  Framing Errors:       %0b", rx_framing_error);
        $display("  Raw String Received: \n%s", received_chars);
        $display("==================================================================");

        // Expected messages:
        // Msg 0: "\r\nBOOT: SoC OK\r\n" (16 bytes)
        // Msg 1: "R1:PASS (9) \r\n"        (14 bytes)
        // Msg 2: "R2:PASS (18) \r\n"         (15 bytes)
        // Msg 3: "ALL PASS!!\r\n"            (12 bytes)
        // Total: 57 bytes

        if (rx_framing_error != 1'b0) begin
            $display("[FAIL] UART framing error detected!");
            $fatal(1, "Framing error");
        end

        if (byte_count != 57) begin
            $display("[FAIL] Byte count mismatch! Expected 57, got %0d", byte_count);
            $fatal(1, "Byte count mismatch");
        end

        // Display received vs expected bytes
        $display("Received string length: %0d", received_chars.len());
        for (int i = 0; i < received_chars.len(); i++) begin
            $display("Byte[%0d]: 0x%02h ('%c')", i, received_chars[i], received_chars[i]);
        end

        // Check exact sequential order
        begin : check_golden
            string golden_str;
            byte golden_bytes[57];
            golden_bytes = '{
                // Msg 0: "\r\nBOOT: SoC OK\r\n" (16 bytes)
                8'h0D, 8'h0A, "B", "O", "O", "T", ":", " ", "S", "o", "C", " ", "O", "K", 8'h0D, 8'h0A,
                // Msg 1: "R1:PASS (9) \r\n" (14 bytes)
                "R", "1", ":", "P", "A", "S", "S", " ", "(", "9", ")", " ", 8'h0D, 8'h0A,
                // Msg 2: "R2:PASS (18) \r\n" (15 bytes)
                "R", "2", ":", "P", "A", "S", "S", " ", "(", "1", "8", ")", " ", 8'h0D, 8'h0A,
                // Msg 3: "ALL PASS!!\r\n" (12 bytes)
                "A", "L", "L", " ", "P", "A", "S", "S", "!", "!", 8'h0D, 8'h0A
            };

            golden_str = "";
            for (int i = 0; i < 57; i++) begin
                golden_str = {golden_str, string'(golden_bytes[i])};
            end

            if (received_chars == golden_str) begin
                $display(">>> [PASS] ALL UART MESSAGES MATCH EXPECTED CONTENT AND ORDER 100%%!");
                $display("    1. BOOT: SoC OK");
                $display("    2. R1:PASS (9)");
                $display("    3. R2:PASS (18)");
                $display("    4. ALL PASS!!");
            end else begin
                $display("[FAIL] Received string does not match golden sequence!");
                $fatal(1, "String mismatch");
            end
        end

        $finish;
    end

endmodule
