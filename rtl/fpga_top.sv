// ============================================================================
// Module Name: fpga_top
// Description: Top-Level FPGA Board Wrapper with Clock/Reset, LEDs & UART Debug
// Target:      Digilent Basys 3 (AMD/Xilinx Artix-7 xc7a35tcpg236-1)
// Author:      RTL Design & Verification Team (Stage 7)
// ============================================================================

`timescale 1ns / 1ps

module fpga_top #(
    parameter string FIRMWARE_HEX = "firmware.hex"
) (
    // Xung nhip 100 MHz tu bo dao dong tren board Basys 3 (Pin W5)
    input  logic        clk_100mhz,

    // Nut nhan Reset (btnC - Pin U18, Active-High)
    input  logic        btn_reset,

    // 16 den LED hien thi trang thai truc quan tren board Basys 3
    output logic [15:0] led,

    // Cong truyen thong noi tiep UART TX (Pin A18 - USB-UART Bridge)
    output logic        uart_tx_out
);

    // ------------------------------------------------------------------------
    // 1. Phan phoi xung nhip toan cuc (Global Clock Buffer)
    // ------------------------------------------------------------------------
    logic sys_clk;
    BUFG u_bufg (
        .I (clk_100mhz),
        .O (sys_clk)
    );

    // ------------------------------------------------------------------------
    // 2. Bo dong bo hoa Reset (Asynchronous Assert, Synchronous Deassert)
    // ------------------------------------------------------------------------
    logic rst_sync_0, rst_sync_1;
    always_ff @(posedge sys_clk or posedge btn_reset) begin
        if (btn_reset) begin
            rst_sync_0 <= 1'b1;
            rst_sync_1 <= 1'b1;
        end else begin
            rst_sync_0 <= 1'b0;
            rst_sync_1 <= rst_sync_0;
        end
    end
    wire sys_rst = rst_sync_1;

    // ------------------------------------------------------------------------
    // 3. Tin hieu noi bo giua soc_top va mach debug
    // ------------------------------------------------------------------------
    logic        soc_trap;
    logic [31:0] soc_debug_out;
    logic        soc_accel_busy;
    logic        soc_accel_done;

    // ------------------------------------------------------------------------
    // 4. Khoi tao Top-Level RISC-V SoC (PicoRV32 + 16KB RAM + Accelerator)
    // ------------------------------------------------------------------------
    soc_top #(
        .FIRMWARE_HEX (FIRMWARE_HEX)
    ) u_soc_top (
        .clk        (sys_clk),
        .rst        (sys_rst),
        .trap       (soc_trap),
        .debug_out  (soc_debug_out),
        .accel_busy (soc_accel_busy),
        .accel_done (soc_accel_done)
    );

    // ------------------------------------------------------------------------
    // 5. Bo dem nhip tim (Heartbeat Alive Counter) & LED Indicators
    // ------------------------------------------------------------------------
    logic [25:0] heartbeat_cnt;
    logic        latched_done;

    always_ff @(posedge sys_clk) begin
        if (sys_rst) begin
            heartbeat_cnt <= '0;
            latched_done  <= 1'b0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
            if (soc_accel_done) begin
                latched_done <= 1'b1;
            end
        end
    end

    // Anh xa LED ro rang, de quan sat va thuyet trinh:
    // led[0]  : Nhip tim CPU/SoC nhap nhay chu ky ~1s (Heartbeat Alive)
    // led[1]  : CPU Trap Indicator (Sang neu CPU gap loi)
    // led[2]  : Accelerator Busy (Sang khi accelerator dang tinh)
    // led[3]  : Accelerator Done (Chot sang khi accelerator hoan tat it nhat 1 luot)
    // led[4]  : Run 1 Active
    // led[5]  : Run 1 PASS (soc_debug_out >= 0xCAFE0001)
    // led[6]  : Run 2 Active
    // led[7]  : Run 2 PASS (soc_debug_out == 0xCAFE0002)
    // led[14:8]: Hien thi cac bit trang thai Debug
    // led[15] : GLOBAL SUCCESS / ALL PASS (0xCAFE0002)
    assign led[0]    = heartbeat_cnt[25];
    assign led[1]    = soc_trap;
    assign led[2]    = soc_accel_busy;
    assign led[3]    = latched_done;
    assign led[4]    = (soc_debug_out == 32'd0) && !soc_trap;
    assign led[5]    = (soc_debug_out >= 32'hCAFE_0001) && (soc_debug_out[31:16] == 16'hCAFE);
    assign led[6]    = (soc_debug_out == 32'hCAFE_0001);
    assign led[7]    = (soc_debug_out == 32'hCAFE_0002);
    assign led[14:8] = soc_debug_out[6:0];
    assign led[15]   = (soc_debug_out == 32'hCAFE_0002);

    // ------------------------------------------------------------------------
    // 6. UART Debug Transmitter (115200 Baud @ 100 MHz Clock)
    // ------------------------------------------------------------------------
    logic       uart_tx_start;
    logic [7:0] uart_tx_byte;
    logic       uart_tx_busy;

    uart_tx #(
        .CLK_FREQ_HZ (100_000_000),
        .BAUD_RATE   (115_200)
    ) u_uart_tx (
        .clk      (sys_clk),
        .rst      (sys_rst),
        .tx_start (uart_tx_start),
        .tx_data  (uart_tx_byte),
        .tx_busy  (uart_tx_busy),
        .tx_pin   (uart_tx_out)
    );

    // ------------------------------------------------------------------------
    // 7. FSM phat thong diep UART bao cao trang thai ra may tinh qua cong COM
    // ------------------------------------------------------------------------
    logic boot_pending_q;
    logic r1_pending_q;
    logic r2_pending_q;
    logic r1_seen_q;
    logic r2_seen_q;

    typedef enum logic [2:0] {
        UART_IDLE       = 3'd0,
        UART_SEND_MSG   = 3'd1,
        UART_WAIT_START = 3'd2,
        UART_WAIT_DONE  = 3'd3
    } uart_fsm_t;

    uart_fsm_t  uart_state_q;
    logic [5:0] msg_idx_q;
    logic [2:0] current_msg_q;

    // ROM chua cac chuoi thong diep ASCII
    // Msg 0: "\r\nBOOT: SoC OK\r\n" (16 bytes)
    // Msg 1: "R1:PASS (9) \r\n"        (14 bytes)
    // Msg 2: "R2:PASS (18) \r\n"         (15 bytes)
    // Msg 3: "ALL PASS!!\r\n"            (12 bytes)
    function automatic logic [7:0] get_msg_char(input [2:0] msg_id, input [5:0] idx);
        case (msg_id)
            3'd0: begin // Boot message (16 bytes)
                case (idx)
                    6'd0: return 8'h0D; 6'd1: return 8'h0A; // \r\n
                    6'd2: return "B";   6'd3: return "O";   6'd4: return "O";   6'd5: return "T";
                    6'd6: return ":";   6'd7: return " ";   6'd8: return "S";   6'd9: return "o";
                    6'd10:return "C";   6'd11:return " ";   6'd12:return "O";   6'd13:return "K";
                    6'd14:return 8'h0D; 6'd15:return 8'h0A;
                    default: return 8'h00;
                endcase
            end
            3'd1: begin // Run 1 PASS (14 bytes)
                case (idx)
                    6'd0: return "R";   6'd1: return "1";   6'd2: return ":";   6'd3: return "P";
                    6'd4: return "A";   6'd5: return "S";   6'd6: return "S";   6'd7: return " ";
                    6'd8: return "(";   6'd9: return "9";   6'd10:return ")";   6'd11:return " ";
                    6'd12:return 8'h0D; 6'd13:return 8'h0A;
                    default: return 8'h00;
                endcase
            end
            3'd2: begin // Run 2 PASS (15 bytes)
                case (idx)
                    6'd0: return "R";   6'd1: return "2";   6'd2: return ":";   6'd3: return "P";
                    6'd4: return "A";   6'd5: return "S";   6'd6: return "S";   6'd7: return " ";
                    6'd8: return "(";   6'd9: return "1";   6'd10:return "8";   6'd11:return ")";
                    6'd12:return " ";   6'd13:return 8'h0D; 6'd14:return 8'h0A;
                    default: return 8'h00;
                endcase
            end
            3'd3: begin // Global PASS (12 bytes)
                case (idx)
                    6'd0: return "A";   6'd1: return "L";   6'd2: return "L";   6'd3: return " ";
                    6'd4: return "P";   6'd5: return "A";   6'd6: return "S";   6'd7: return "S";
                    6'd8: return "!";   6'd9: return "!";   6'd10:return 8'h0D; 6'd11:return 8'h0A;
                    default: return 8'h00;
                endcase
            end
            default: return 8'h00;
        endcase
    endfunction

    function automatic logic [5:0] get_msg_len(input [2:0] msg_id);
        case (msg_id)
            3'd0: return 6'd16;
            3'd1: return 6'd14;
            3'd2: return 6'd15;
            3'd3: return 6'd12;
            default: return 6'd0;
        endcase
    endfunction

    // Catch pending status events exactly ONCE upon rising event
    always_ff @(posedge sys_clk) begin
        if (sys_rst) begin
            boot_pending_q <= 1'b1; // Trigger BOOT immediately upon reset release
            r1_pending_q   <= 1'b0;
            r2_pending_q   <= 1'b0;
            r1_seen_q      <= 1'b0;
            r2_seen_q      <= 1'b0;
        end else begin
            if (soc_debug_out == 32'hCAFE_0001 && !r1_seen_q) begin
                r1_pending_q <= 1'b1;
                r1_seen_q    <= 1'b1;
            end
            if (soc_debug_out == 32'hCAFE_0002 && !r2_seen_q) begin
                r2_pending_q <= 1'b1;
                r2_seen_q    <= 1'b1;
            end

            // Clear pending flag once the respective message transmission is dispatched
            if (uart_state_q == UART_IDLE) begin
                if (boot_pending_q) begin
                    boot_pending_q <= 1'b0;
                end else if (r1_pending_q) begin
                    r1_pending_q   <= 1'b0;
                end else if (r2_pending_q) begin
                    r2_pending_q   <= 1'b0;
                end
            end
        end
    end

    // UART Transmission FSM (Strict in-order: BOOT -> RUN 1 -> RUN 2 -> ALL PASS)
    always_ff @(posedge sys_clk) begin
        if (sys_rst) begin
            uart_state_q   <= UART_IDLE;
            uart_tx_start  <= 1'b0;
            uart_tx_byte   <= '0;
            msg_idx_q      <= '0;
            current_msg_q  <= '0;
        end else begin
            uart_tx_start <= 1'b0;

            case (uart_state_q)
                UART_IDLE: begin
                    msg_idx_q <= '0;
                    if (boot_pending_q) begin
                        current_msg_q <= 3'd0;
                        uart_state_q  <= UART_SEND_MSG;
                    end else if (r1_pending_q) begin
                        current_msg_q <= 3'd1;
                        uart_state_q  <= UART_SEND_MSG;
                    end else if (r2_pending_q) begin
                        current_msg_q <= 3'd2;
                        uart_state_q  <= UART_SEND_MSG;
                    end
                end

                UART_SEND_MSG: begin
                    if (!uart_tx_busy) begin
                        uart_tx_byte  <= get_msg_char(current_msg_q, msg_idx_q);
                        uart_tx_start <= 1'b1;
                        uart_state_q  <= UART_WAIT_START;
                    end
                end

                UART_WAIT_START: begin
                    // Wait for uart_tx to recognize tx_start and raise tx_busy
                    if (uart_tx_busy) begin
                        uart_state_q <= UART_WAIT_DONE;
                    end
                end

                UART_WAIT_DONE: begin
                    // Wait for uart_tx to completely finish sending the byte (tx_busy falls to 0)
                    if (!uart_tx_busy) begin
                        if (msg_idx_q + 1'b1 < get_msg_len(current_msg_q)) begin
                            msg_idx_q    <= msg_idx_q + 1'b1;
                            uart_state_q <= UART_SEND_MSG;
                        end else begin
                            // Chain Msg 3 (ALL PASS) directly after Msg 2 (Run 2 PASS)
                            if (current_msg_q == 3'd2) begin
                                current_msg_q <= 3'd3;
                                msg_idx_q     <= '0;
                                uart_state_q  <= UART_SEND_MSG;
                            end else begin
                                uart_state_q  <= UART_IDLE;
                            end
                        end
                    end
                end

                default: uart_state_q <= UART_IDLE;
            endcase
        end
    end

endmodule

