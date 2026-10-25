// ============================================================================
// Module Name: conv_window_reader
// Description: Synchronous RAM Buffers & Sequencer for 3x3 Window Extraction
// Target:      RISC-V INT8 Convolution Accelerator (Stage 3)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module conv_window_reader #(
    parameter int IMG_WIDTH   = 32,
    parameter int IMG_HEIGHT  = 32,
    parameter int KERNEL_SIZE = 3
) (
    input  logic                    clk,
    input  logic                    rst,             // Reset dong bo, active-high

    // Cong nap du lieu cho Input Buffer (32x32 = 1024 bytes signed INT8)
    input  logic                    ibuf_wr_en,
    input  logic [9:0]              ibuf_wr_addr,
    input  logic signed [7:0]       ibuf_wr_data,

    // Cong nap du lieu cho Weight Buffer (9 bytes signed INT8)
    input  logic                    wbuf_wr_en,
    input  logic [3:0]              wbuf_wr_addr,
    input  logic signed [7:0]       wbuf_wr_data,

    // Giao tiep dieu khien va toa do cua so can tinh (out_row, out_col)
    input  logic                    start_window,    // Xung 1 chu ky kich hoat doc & tinh cua so
    input  logic [4:0]              out_row,         // Toa do hang cua pixel output (0..29)
    input  logic [4:0]              out_col,         // Toa do cot cua pixel output (0..29)

    // Tin hieu trang thai va ket qua dau ra cua cua so 3x3
    output logic                    busy,            // Bao dang ban doc & tinh toan cua so
    output logic                    window_done,     // Xung bao hoan tat cua so dung 1 chu ky
    output logic signed [31:0]      window_result,   // Ket qua tong tich 9 cap signed INT32

    // Tin hieu quan sat (Monitoring) phuc vu kiem chung tung cap toan hang
    output logic [3:0]              mon_pair_idx,    // Chi so cap toan hang dang xu ly (0..8)
    output logic signed [7:0]       mon_x,           // Gia tri x cap cho dot9_int8
    output logic signed [7:0]       mon_w,           // Gia tri w cap cho dot9_int8
    output logic                    mon_valid,       // Co valid cap cho dot9_int8
    output logic                    mon_ready        // Co ready tu dot9_int8
);

    // ------------------------------------------------------------------------
    // Dinh nghia cac trang thai FSM Sequencer
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        SEQ_IDLE       = 3'd0, // Cho xung start_window
        SEQ_START_DOT9 = 3'd1, // Phat xung start 1 chu ky toi dot9_int8
        SEQ_REQ_READ   = 3'd2, // Phat dia chi doc toi Input Buffer va Weight Buffer
        SEQ_WAIT_RAM   = 3'd3, // Cho RAM doc dong bo (1 chu ky do tre - read latency)
        SEQ_FEED_PAIR  = 3'd4, // Cap toan hang cho dot9_int8 va cho bat tay valid-ready
        SEQ_WAIT_DONE  = 3'd5, // Cho dot9_int8 tinh xong va phat cờ done
        SEQ_DONE       = 3'd6  // Chot window_result va phat window_done 1 chu ky
    } seq_state_t;

    seq_state_t state_q, state_d;

    // Thanh ghi luu tru toa do cua so dang tinh
    logic [4:0] reg_row_q, reg_row_d;
    logic [4:0] reg_col_q, reg_col_d;

    // Bo dem chi so cap toan hang trong cua so 3x3 (0..8)
    logic [3:0] k_q, k_d;

    // Tin hieu giao tiep RAM
    logic [9:0]              ibuf_rd_addr;
    logic signed [7:0]       ibuf_rd_data;
    logic [3:0]              wbuf_rd_addr;
    logic signed [7:0]       wbuf_rd_data;

    // Thanh ghi dem toan hang chot tu RAM sau chu ky doc hop le
    logic signed [7:0]       reg_x_q, reg_x_d;
    logic signed [7:0]       reg_w_q, reg_w_d;

    // Tin hieu dieu khien noi bo toi dot9_int8
    logic                    dot9_start;
    logic                    dot9_in_valid;
    logic                    dot9_in_ready;
    logic signed [7:0]       dot9_x;
    logic signed [7:0]       dot9_w;
    logic                    dot9_busy;
    logic                    dot9_done;
    logic signed [31:0]      dot9_result;

    // Tin hieu bat tay giua Sequencer va dot9_int8
    logic                    dot9_accept;
    assign dot9_accept = dot9_in_valid && dot9_in_ready;

    // Gan tin hieu quan sat ra ngoai cho testbench
    assign mon_pair_idx = k_q;
    assign mon_x        = dot9_x;
    assign mon_w        = dot9_w;
    assign mon_valid    = dot9_in_valid;
    assign mon_ready    = dot9_in_ready;

    // ------------------------------------------------------------------------
    // Ham tinh dia chi Input Buffer cho phan tu thu k (0..8) trong cua so (row, col)
    // Cua so 3x3 khong lat kernel:
    //   k = 0..2: hang row+0, cot col+0..col+2
    //   k = 3..5: hang row+1, cot col+0..col+2
    //   k = 6..8: hang row+2, cot col+0..col+2
    // Dia chi = (hang * 32) + cot = (hang << 5) | cot
    // ------------------------------------------------------------------------
    function automatic logic [9:0] calc_ibuf_addr(
        input logic [4:0] r,
        input logic [4:0] c,
        input logic [3:0] idx
    );
        logic [1:0] dr, dc;
        logic [5:0] pix_r, pix_c;
        begin
            case (idx)
                4'd0: begin dr = 2'd0; dc = 2'd0; end
                4'd1: begin dr = 2'd0; dc = 2'd1; end
                4'd2: begin dr = 2'd0; dc = 2'd2; end
                4'd3: begin dr = 2'd1; dc = 2'd0; end
                4'd4: begin dr = 2'd1; dc = 2'd1; end
                4'd5: begin dr = 2'd1; dc = 2'd2; end
                4'd6: begin dr = 2'd2; dc = 2'd0; end
                4'd7: begin dr = 2'd2; dc = 2'd1; end
                4'd8: begin dr = 2'd2; dc = 2'd2; end
                default: begin dr = 2'd0; dc = 2'd0; end
            endcase
            pix_r = {1'b0, r} + {4'd0, dr};
            pix_c = {1'b0, c} + {4'd0, dc};
            return (pix_r[4:0] << 5) | pix_c[4:0];
        end
    endfunction

    // ------------------------------------------------------------------------
    // Khoi tao Input Buffer (1024 bytes - Block RAM Inference)
    // ------------------------------------------------------------------------
    ram_sync_read #(
        .DATA_WIDTH (8),
        .ADDR_WIDTH (10),
        .DEPTH      (1024),
        .RAM_STYLE  ("block")
    ) u_input_buffer (
        .clk     (clk),
        .wr_en   (ibuf_wr_en),
        .wr_addr (ibuf_wr_addr),
        .wr_data (ibuf_wr_data),
        .rd_addr (ibuf_rd_addr),
        .rd_data (ibuf_rd_data)
    );

    // ------------------------------------------------------------------------
    // Khoi tao Weight Buffer (9 bytes - Distributed LUTRAM Inference)
    // ------------------------------------------------------------------------
    ram_sync_read #(
        .DATA_WIDTH (8),
        .ADDR_WIDTH (4),
        .DEPTH      (9),
        .RAM_STYLE  ("distributed")
    ) u_weight_buffer (
        .clk     (clk),
        .wr_en   (wbuf_wr_en),
        .wr_addr (wbuf_wr_addr),
        .wr_data (wbuf_wr_data),
        .rd_addr (wbuf_rd_addr),
        .rd_data (wbuf_rd_data)
    );

    // ------------------------------------------------------------------------
    // Khoi tao Lõi tính 9 cap dot9_int8 tu Giai doan 2 (Tai su dung 100%)
    // ------------------------------------------------------------------------
    dot9_int8 u_dot9 (
        .clk      (clk),
        .rst      (rst),
        .start    (dot9_start),
        .in_valid (dot9_in_valid),
        .in_ready (dot9_in_ready),
        .x        (dot9_x),
        .w        (dot9_w),
        .busy     (dot9_busy),
        .done     (dot9_done),
        .result   (dot9_result)
    );

    // ------------------------------------------------------------------------
    // Logic to hop dieu khien FSM Sequencer (Next-State Logic)
    // ------------------------------------------------------------------------
    always_comb begin
        // Gia tri mac dinh tranh tao latch
        state_d       = state_q;
        reg_row_d     = reg_row_q;
        reg_col_d     = reg_col_q;
        k_d           = k_q;
        reg_x_d       = reg_x_q;
        reg_w_d       = reg_w_q;

        // Tin hieu dieu khien mac dinh
        dot9_start    = 1'b0;
        dot9_in_valid = 1'b0;
        dot9_x        = reg_x_q;
        dot9_w        = reg_w_q;
        busy          = (state_q != SEQ_IDLE);
        window_done   = 1'b0;

        // Phat dia chi doc RAM dua tren toa do va chi so k_q
        ibuf_rd_addr  = calc_ibuf_addr(reg_row_q, reg_col_q, k_q);
        wbuf_rd_addr  = k_q;

        case (state_q)
            SEQ_IDLE: begin
                k_d = 4'd0;
                if (start_window && !rst) begin
                    reg_row_d = out_row;
                    reg_col_d = out_col;
                    state_d   = SEQ_START_DOT9;
                end
            end

            SEQ_START_DOT9: begin
                // Phat xung start dung 1 chu ky toi dot9_int8
                dot9_start = 1'b1;
                k_d        = 4'd0;
                // Chuyen sang phat dia chi doc cap dau tien k=0
                state_d    = SEQ_REQ_READ;
            end

            SEQ_REQ_READ: begin
                // Tai chu ky nay, ibuf_rd_addr va wbuf_rd_addr duoc cap on dinh toi RAM.
                // Tai posedge tiep theo, RAM chot dia chi doc.
                state_d = SEQ_WAIT_RAM;
            end

            SEQ_WAIT_RAM: begin
                // Chu ky cho do tre doc 1 chu ky cua RAM dong bo.
                // Cuoi chu ky nay (tai posedge tiep theo), ibuf_rd_data va wbuf_rd_data da xuat hien hop le.
                state_d = SEQ_FEED_PAIR;
            end

            SEQ_FEED_PAIR: begin
                // Du lieu doc tu RAM da hop le tai dau ra RAM.
                // Chot du lieu vao reg_x, reg_w de giu on dinh tuyet doi neu gap backpressure.
                reg_x_d       = ibuf_rd_data;
                reg_w_d       = wbuf_rd_data;
                dot9_x        = ibuf_rd_data;
                dot9_w        = wbuf_rd_data;
                dot9_in_valid = 1'b1; // Báo dữ liệu sẵn sàng

                // Bat tay voi dot9_int8:
                // Neu dot9_in_ready == 0: tiep tuc o lai SEQ_FEED_PAIR, giu nguyen valid va x, w.
                if (dot9_accept) begin
                    // Bat tay thanh cong! dot9_int8 da nhan cap k_q.
                    if (k_q == 4'd8) begin
                        // Da cap du ca 9 cap toan hang! Chuyen sang cho dot9 hoan tat
                        state_d = SEQ_WAIT_DONE;
                    end else begin
                        // Chuyen sang doc cap tiep theo (k + 1)
                        k_d     = k_q + 4'd1;
                        state_d = SEQ_REQ_READ;
                    end
                end
            end

            SEQ_WAIT_DONE: begin
                // Cho den khi dot9_int8 phat co done
                if (dot9_done) begin
                    state_d = SEQ_DONE;
                end
            end

            SEQ_DONE: begin
                // Phat xung window_done dung 1 chu ky
                window_done = 1'b1;
                state_d     = SEQ_IDLE;
            end

            default: begin
                state_d = SEQ_IDLE;
                k_d     = 4'd0;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Cap nhat thanh ghi tuan tu (Sequential Register Update)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q       <= SEQ_IDLE;
            reg_row_q     <= 5'd0;
            reg_col_q     <= 5'd0;
            k_q           <= 4'd0;
            reg_x_q       <= 8'sd0;
            reg_w_q       <= 8'sd0;
            window_result <= 32'sd0;
        end else begin
            state_q   <= state_d;
            reg_row_q <= reg_row_d;
            reg_col_q <= reg_col_d;
            k_q       <= k_d;
            reg_x_q   <= reg_x_d;
            reg_w_q   <= reg_w_d;

            // Chot ket qua khi dot9_int8 bao done
            if (state_q == SEQ_WAIT_DONE && dot9_done) begin
                window_result <= dot9_result;
            end
        end
    end

endmodule
