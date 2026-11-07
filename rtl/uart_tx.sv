// ============================================================================
// Module Name: uart_tx
// Description: Compact UART Transmitter (8-N-1, 115200 Baud @ 100 MHz Clock)
// Target:      AMD/Xilinx Artix-7 (Digilent Basys 3 - RsTx Pin A18)
// Author:      RTL Design & Verification Team (Stage 7)
// ============================================================================

`timescale 1ns / 1ps

module uart_tx #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200
) (
    input  logic       clk,
    input  logic       rst,

    // Giao tiep du lieu
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx_busy,

    // Chân truyen noi tiep UART vat ly
    output logic       tx_pin
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE; // 868 chu ky tai 100 MHz

    typedef enum logic [2:0] {
        STATE_IDLE  = 3'd0,
        STATE_START = 3'd1,
        STATE_DATA  = 3'd2,
        STATE_STOP  = 3'd3
    } uart_state_t;

    uart_state_t state_q;
    logic [15:0] clk_cnt_q;
    logic [2:0]  bit_idx_q;
    logic [7:0]  shifter_q;
    logic        tx_out_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q   <= STATE_IDLE;
            clk_cnt_q <= '0;
            bit_idx_q <= '0;
            shifter_q <= '0;
            tx_out_q  <= 1'b1; // UART idle o muc cao
        end else begin
            case (state_q)
                STATE_IDLE: begin
                    tx_out_q  <= 1'b1;
                    clk_cnt_q <= '0;
                    bit_idx_q <= '0;
                    if (tx_start) begin
                        shifter_q <= tx_data;
                        state_q   <= STATE_START;
                    end
                end

                STATE_START: begin
                    tx_out_q <= 1'b0; // Start bit = 0
                    if (clk_cnt_q < CLKS_PER_BIT - 1) begin
                        clk_cnt_q <= clk_cnt_q + 1'b1;
                    end else begin
                        clk_cnt_q <= '0;
                        state_q   <= STATE_DATA;
                    end
                end

                STATE_DATA: begin
                    tx_out_q <= shifter_q[bit_idx_q];
                    if (clk_cnt_q < CLKS_PER_BIT - 1) begin
                        clk_cnt_q <= clk_cnt_q + 1'b1;
                    end else begin
                        clk_cnt_q <= '0;
                        if (bit_idx_q < 3'd7) begin
                            bit_idx_q <= bit_idx_q + 1'b1;
                        end else begin
                            bit_idx_q <= '0;
                            state_q   <= STATE_STOP;
                        end
                    end
                end

                STATE_STOP: begin
                    tx_out_q <= 1'b1; // Stop bit = 1
                    if (clk_cnt_q < CLKS_PER_BIT - 1) begin
                        clk_cnt_q <= clk_cnt_q + 1'b1;
                    end else begin
                        clk_cnt_q <= '0;
                        state_q   <= STATE_IDLE;
                    end
                end

                default: begin
                    state_q <= STATE_IDLE;
                end
            endcase
        end
    end

    assign tx_pin  = tx_out_q;
    assign tx_busy = (state_q != STATE_IDLE);

endmodule

