// ============================================================================
// Module Name: dot9_int8
// Description: FSM Controller & Handshake Wrapper for 9-Element INT8 Dot Product
// Target:      RISC-V INT8 Convolution Accelerator (Stage 2)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module dot9_int8 (
    input  logic               clk,         // Xung dong ho he thong
    input  logic               rst,         // Reset dong bo, active-high
    input  logic               start,       // Xung start 1 chu ky tu khoi dieu khien
    input  logic               in_valid,    // Bao toan hang dau vao (x, w) hop le
    output logic               in_ready,    // Accelerator san sang nhan du lieu
    input  logic signed [7:0]  x,           // Toan hang dau vao signed INT8 (pixel/activation)
    input  logic signed [7:0]  w,           // Toan hang dau vao signed INT8 (weight/kernel)
    output logic               busy,        // Bao accelerator dang ban thuc hien tac vu
    output logic               done,        // Xung bao hoan tat dung 1 chu ky
    output logic signed [31:0] result       // Ket qua tong tich 9 cap signed INT32
);

    // ------------------------------------------------------------------------
    // Dinh nghia cac trang thai FSM ro rang (5 trang thai)
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        STATE_IDLE       = 3'd0,  // Nghi, cho xung start
        STATE_CLEAR      = 3'd1,  // Phat clear cho MAC, khong nhan du lieu
        STATE_ACCUMULATE = 3'd2,  // Bat in_ready=1, nhan du 9 cap toan hang
        STATE_CAPTURE    = 3'd3,  // Chot result tu mac_acc sau khi du 9 tich
        STATE_DONE       = 3'd4   // Phat xung done=1 dung 1 chu ky, result hop le
    } state_t;

    state_t state_q, state_d;

    // Bo dem so cap toan hang da nhan (0..9, can toi thieu 4 bit)
    logic [3:0] count_q, count_d;

    // Tin hieu bat tay hop le: chi nhan toan hang khi ca valid va ready deu bat
    logic accept;

    // Tin hieu dieu khien noi bo toi khoi mac_int8
    logic mac_clear;
    logic mac_valid;
    logic signed [31:0] mac_acc;

    // ------------------------------------------------------------------------
    // Logic to hop cho giao tiep bat tay va dieu khien
    // ------------------------------------------------------------------------
    // Handshake: Du lieu duoc nhan khi in_valid va in_ready cung bang 1
    assign accept = in_valid && in_ready;

    // in_ready chi bang 1 trong trang thai ACCUMULATE va khi khong co reset
    assign in_ready = (state_q == STATE_ACCUMULATE) && !rst;

    // busy tich cuc o tat ca cac trang thai khac IDLE
    assign busy = (state_q != STATE_IDLE);

    // done la xung dung 1 chu ky khi FSM o trang thai DONE
    assign done = (state_q == STATE_DONE);

    // Phat tin hieu clear 1 chu ky toi MAC trong trang thai CLEAR
    assign mac_clear = (state_q == STATE_CLEAR);

    // mac_valid chuyen thang tin hieu accept toi MAC
    assign mac_valid = accept;

    // ------------------------------------------------------------------------
    // Tai su dung khoi mac_int8 tu Giai doan 1 (Direct Reuse)
    // ------------------------------------------------------------------------
    mac_int8 u_mac (
        .clk   (clk),
        .rst   (rst),
        .clear (mac_clear),
        .valid (mac_valid),
        .x     (x),
        .w     (w),
        .acc   (mac_acc)
    );

    // ------------------------------------------------------------------------
    // Logic chuyen trang thai FSM va bo dem (Combinational Next-State Logic)
    // ------------------------------------------------------------------------
    always_comb begin
        // Gia tri mac dinh tranh tao latch
        state_d = state_q;
        count_d = count_q;

        case (state_q)
            STATE_IDLE: begin
                count_d = 4'd0;
                // Chi nhan start tai canh len khi o IDLE va rst=0
                if (start && !rst) begin
                    state_d = STATE_CLEAR;
                end
            end

            STATE_CLEAR: begin
                count_d = 4'd0;
                // Sau 1 chu ky clear MAC, chuyen sang tich luy du lieu
                state_d = STATE_ACCUMULATE;
            end

            STATE_ACCUMULATE: begin
                if (accept) begin
                    count_d = count_q + 4'd1;
                    // Khi dang o cap thu 8 (count_q=8) va accept=1:
                    // Day chinh la cap thu 9! Chuyen sang trang thai CAPTURE.
                    if (count_q == 4'd8) begin
                        state_d = STATE_CAPTURE;
                    end
                end
                // Neu accept=0: count_d giu nguyen count_q, mac_valid=0
            end

            STATE_CAPTURE: begin
                // Tai CAPTURE: in_ready da ha xuong 0, khong nhan cap thu 10.
                // mac_acc cua mac_int8 da hoan tat NBA cap nhat tich thu 9.
                // Chuyen sang DONE de phat xung bao hoan tat.
                state_d = STATE_DONE;
            end

            STATE_DONE: begin
                // Sau 1 chu ky DONE, tro ve IDLE de san sang nhan tac vu moi
                state_d = STATE_IDLE;
            end

            default: begin
                state_d = STATE_IDLE;
                count_d = 4'd0;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Cap nhat thanh ghi tuan tu (Sequential State & Register Update)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= STATE_IDLE;
            count_q <= 4'd0;
            result  <= 32'sd0;
        end else begin
            state_q <= state_d;
            count_q <= count_d;

            // Chot result tai canh chuyen tu CAPTURE sang DONE:
            // O chu ky CAPTURE, mac_acc da co du 9 tich on dinh.
            // Result duoc chot tai day dam bao hop le 100% trong suot chu ky DONE=1.
            // Result giu nguyen gia tri nay cho toi khi tac vu tiep theo hoan tat hoac reset.
            if (state_q == STATE_CAPTURE) begin
                result <= mac_acc;
            end
        end
    end

endmodule
