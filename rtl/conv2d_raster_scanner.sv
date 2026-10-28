// ============================================================================
// Module Name: conv2d_raster_scanner
// Description: Raster Scanner & Controller for 2D INT8 Convolution Accelerator
// Target:      RISC-V INT8 Convolution Accelerator (Stage 4)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module conv2d_raster_scanner #(
    parameter int IMG_WIDTH   = 32,
    parameter int IMG_HEIGHT  = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int STRIDE      = 1,
    parameter int PADDING     = 0
) (
    input  logic                    clk,
    input  logic                    rst,             // Reset dong bo, active-high
    input  logic                    start,           // Xung bat dau quet toan bo anh (1 chu ky)
    output logic                    busy,            // Bao he thong dang ban tinh toan
    output logic                    done,            // Xung bao hoan tat toan bo anh (1 chu ky)

    // Giao tiep nap du lieu cho Input Buffer (32x32 = 1024 bytes signed INT8)
    input  logic                    ibuf_wr_en,
    input  logic [9:0]              ibuf_wr_addr,
    input  logic signed [7:0]       ibuf_wr_data,

    // Giao tiep nap du lieu cho Weight Buffer (9 bytes signed INT8)
    input  logic                    wbuf_wr_en,
    input  logic [3:0]              wbuf_wr_addr,
    input  logic signed [7:0]       wbuf_wr_data,

    // Output Streaming Interface (Valid / Ready handshake)
    output logic                    result_valid,    // Bao du lieu output hop le
    input  logic                    result_ready,    // Consumer san sang nhan ket qua
    output logic signed [31:0]      result_data,     // Ket qua tich chap signed INT32
    output logic [9:0]              result_addr      // Dia chi tuyen tinh output (0..899)
);

    // ------------------------------------------------------------------------
    // Tinh toan kich thuoc ma tran output va do rong dia chi
    // OUT_WIDTH  = 32 - 3 + 1 = 30
    // OUT_HEIGHT = 32 - 3 + 1 = 30
    // TOTAL_OUTPUTS = 30 * 30 = 900
    // ------------------------------------------------------------------------
    localparam int OUT_WIDTH     = IMG_WIDTH - KERNEL_SIZE + 1;
    localparam int OUT_HEIGHT    = IMG_HEIGHT - KERNEL_SIZE + 1;
    localparam int TOTAL_OUTPUTS = OUT_WIDTH * OUT_HEIGHT;
    localparam int ADDR_WIDTH    = (TOTAL_OUTPUTS > 1) ? $clog2(TOTAL_OUTPUTS) : 1; // 10 bit cho 900 outputs
    localparam int ROW_BITS      = (OUT_HEIGHT > 1) ? $clog2(OUT_HEIGHT) : 1;       // 5 bit (0..29)
    localparam int COL_BITS      = (OUT_WIDTH > 1) ? $clog2(OUT_WIDTH) : 1;         // 5 bit (0..29)

    // ------------------------------------------------------------------------
    // Dinh nghia cac trang thai FSM dieu khien Raster Scan
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        STATE_IDLE          = 3'd0, // Cho xung start de bat dau luot quet
        STATE_START_WINDOW  = 3'd1, // Phat start_window 1 chu ky toi conv_window_reader
        STATE_WAIT_WINDOW   = 3'd2, // Cho window_done tu conv_window_reader
        STATE_OUTPUT_RESULT = 3'd3, // Phat result_valid, giu du lieu va cho result_ready
        STATE_NEXT_POSITION = 3'd4, // Cap nhat toa do (row, col) tiep theo
        STATE_DONE          = 3'd5  // Phat xung done 1 chu ky sau khi ket qua cuoi duoc nhan
    } scan_state_t;

    scan_state_t state_q, state_d;

    // Bo dem toa do cua so hien tai: out_row (0..29), out_col (0..29)
    logic [ROW_BITS-1:0] cur_row_q, cur_row_d;
    logic [COL_BITS-1:0] cur_col_q, cur_col_d;

    // Thanh ghi chot ket qua va dia chi output
    logic signed [31:0]  reg_result_data_q, reg_result_data_d;
    logic [9:0]          reg_result_addr_q, reg_result_addr_d;

    // Tin hieu ket noi noi bo toi conv_window_reader
    logic                win_start_window;
    logic [4:0]          win_out_row;
    logic [4:0]          win_out_col;
    logic                win_busy;
    logic                win_window_done;
    logic signed [31:0]  win_window_result;

    // Toa do dua vao conv_window_reader lay tu bo dem toa do hien tai
    assign win_out_row = 5'(cur_row_q);
    assign win_out_col = 5'(cur_col_q);

    // ------------------------------------------------------------------------
    // Khoi tao DUY NHAT 1 instance conv_window_reader (Tai su dung phan cung)
    // ------------------------------------------------------------------------
    conv_window_reader #(
        .IMG_WIDTH   (IMG_WIDTH),
        .IMG_HEIGHT  (IMG_HEIGHT),
        .KERNEL_SIZE (KERNEL_SIZE)
    ) u_window_reader (
        .clk           (clk),
        .rst           (rst),
        .ibuf_wr_en    (ibuf_wr_en),
        .ibuf_wr_addr  (ibuf_wr_addr),
        .ibuf_wr_data  (ibuf_wr_data),
        .wbuf_wr_en    (wbuf_wr_en),
        .wbuf_wr_addr  (wbuf_wr_addr),
        .wbuf_wr_data  (wbuf_wr_data),
        .start_window  (win_start_window),
        .out_row       (win_out_row),
        .out_col       (win_out_col),
        .busy          (win_busy),
        .window_done   (win_window_done),
        .window_result (win_window_result),
        .mon_pair_idx  (),
        .mon_x         (),
        .mon_w         (),
        .mon_valid     (),
        .mon_ready     ()
    );

    // ------------------------------------------------------------------------
    // Logic to hop dieu khien FSM va Handshake (Next-State Logic)
    // ------------------------------------------------------------------------
    always_comb begin
        // Gia tri mac dinh chong tao latch
        state_d           = state_q;
        cur_row_d         = cur_row_q;
        cur_col_d         = cur_col_q;
        reg_result_data_d = reg_result_data_q;
        reg_result_addr_d = reg_result_addr_q;
        win_start_window  = 1'b0;

        case (state_q)
            // ----------------------------------------------------------------
            // STATE_IDLE: Cho xung start bat dau luot quet
            // ----------------------------------------------------------------
            STATE_IDLE: begin
                cur_row_d = '0;
                cur_col_d = '0;
                if (start && !rst) begin
                    state_d = STATE_START_WINDOW;
                end
            end

            // ----------------------------------------------------------------
            // STATE_START_WINDOW: Phat xung start_window dung 1 chu ky
            // ----------------------------------------------------------------
            STATE_START_WINDOW: begin
                win_start_window = 1'b1;
                state_d          = STATE_WAIT_WINDOW;
            end

            // ----------------------------------------------------------------
            // STATE_WAIT_WINDOW: Cho conv_window_reader tinh xong (window_done)
            // ----------------------------------------------------------------
            STATE_WAIT_WINDOW: begin
                if (win_window_done) begin
                    // Chot ket qua va tinh dia chi tuyen tinh: addr = row * OUT_WIDTH + col
                    reg_result_data_d = win_window_result;
                    reg_result_addr_d = 10'((cur_row_q * OUT_WIDTH) + cur_col_q);
                    state_d           = STATE_OUTPUT_RESULT;
                end
            end

            // ----------------------------------------------------------------
            // STATE_OUTPUT_RESULT: Phat result_valid va bat tay result_ready
            // Neu result_ready = 0: Giu nguyen valid, data, addr (Chong backpressure)
            // ----------------------------------------------------------------
            STATE_OUTPUT_RESULT: begin
                if (result_ready) begin
                    // Ket qua da duoc consumer tiep nhan!
                    // Kiem tra da den phan tu cuoi cung (29, 29) hay chua
                    if ((cur_row_q == (ROW_BITS)'(OUT_HEIGHT - 1)) &&
                        (cur_col_q == (COL_BITS)'(OUT_WIDTH - 1))) begin
                        state_d = STATE_DONE;
                    end else begin
                        state_d = STATE_NEXT_POSITION;
                    end
                end
            end

            // ----------------------------------------------------------------
            // STATE_NEXT_POSITION: Tang toa do theo thu tu Raster Scan (Hang truoc, Cot sau)
            // ----------------------------------------------------------------
            STATE_NEXT_POSITION: begin
                if (cur_col_q == (COL_BITS)'(OUT_WIDTH - 1)) begin
                    cur_col_d = '0;
                    cur_row_d = cur_row_q + 1'b1;
                end else begin
                    cur_col_d = cur_col_q + 1'b1;
                end
                state_d = STATE_START_WINDOW;
            end

            // ----------------------------------------------------------------
            // STATE_DONE: Phat xung done dung 1 chu ky, quay lai IDLE
            // ----------------------------------------------------------------
            STATE_DONE: begin
                state_d = STATE_IDLE;
            end

            default: begin
                state_d           = STATE_IDLE;
                cur_row_d         = '0;
                cur_col_d         = '0;
                reg_result_data_d = 32'sd0;
                reg_result_addr_d = 10'd0;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Cap nhat thanh ghi tuan tu (Sequential Register Update)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q           <= STATE_IDLE;
            cur_row_q         <= '0;
            cur_col_q         <= '0;
            reg_result_data_q <= 32'sd0;
            reg_result_addr_q <= 10'd0;
        end else begin
            state_q           <= state_d;
            cur_row_q         <= cur_row_d;
            cur_col_q         <= cur_col_d;
            reg_result_data_q <= reg_result_data_d;
            reg_result_addr_q <= reg_result_addr_d;
        end
    end

    // ------------------------------------------------------------------------
    // Tin hieu dau ra
    // ------------------------------------------------------------------------
    // busy tich cuc khi FSM o bat ky trang thai nao khac IDLE
    assign busy         = (state_q != STATE_IDLE);

    // done phat xung dung 1 chu ky tai STATE_DONE
    assign done         = (state_q == STATE_DONE);

    // result_valid tich cuc khi o trang thai OUTPUT_RESULT
    assign result_valid = (state_q == STATE_OUTPUT_RESULT);

    // result_data va result_addr duoc xuat truc tiep tu thanh ghi chot on dinh
    assign result_data  = reg_result_data_q;
    assign result_addr  = reg_result_addr_q;

endmodule
