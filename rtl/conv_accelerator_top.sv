// ============================================================================
// Module Name: conv_accelerator_top
// Description: Top-Level Convolution Accelerator Module (Stage 5)
// Target:      RISC-V INT8 Convolution Accelerator (Artix-7 xc7a35tcpg236-1)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module conv_accelerator_top #(
    parameter int IMG_WIDTH   = 32,
    parameter int IMG_HEIGHT  = 32,
    parameter int KERNEL_SIZE = 3,
    parameter int STRIDE      = 1,
    parameter int PADDING     = 0
) (
    // He thong xung nhip va reset
    input  logic                          clk,
    input  logic                          rst,             // Reset dong bo, active-high
    input  logic                          start,           // Xung khoi dong quet toan bo anh (1 chu ky)
    output logic                          busy,            // Bao bo tang toc dang ban tinh toan
    output logic                          done,            // Xung bao hoan tat toan bo 900 output da ghi xong

    // Giao tiep nap du lieu Input Buffer (32x32 = 1024 bytes signed INT8)
    input  logic                          ibuf_wr_en,
    input  logic [9:0]                    ibuf_wr_addr,
    input  logic signed [7:0]             ibuf_wr_data,

    // Giao tiep nap du lieu Weight Buffer (3x3 = 9 bytes signed INT8)
    input  logic                          wbuf_wr_en,
    input  logic [3:0]                    wbuf_wr_addr,
    input  logic signed [7:0]             wbuf_wr_data,

    // Giao tiep doc du lieu Output Buffer (30x30 = 900 words signed INT32)
    // Synchronous Read: Chu ky N dat obuf_rd_addr -> Chu ky N+1 obuf_rd_data hop le
    input  logic [9:0]                    obuf_rd_addr,
    output logic signed [31:0]            obuf_rd_data
);

    // ------------------------------------------------------------------------
    // Tinh toan thong so kich thuoc ma tran output
    // ------------------------------------------------------------------------
    localparam int OUT_WIDTH     = IMG_WIDTH - KERNEL_SIZE + 1;  // 30
    localparam int OUT_HEIGHT    = IMG_HEIGHT - KERNEL_SIZE + 1; // 30
    localparam int TOTAL_OUTPUTS = OUT_WIDTH * OUT_HEIGHT;       // 900
    localparam int ADDR_WIDTH    = 10;                           // 10 bit cho 0..899

    // ------------------------------------------------------------------------
    // Tin hieu ket noi noi bo giua Scanner va Output Buffer
    // ------------------------------------------------------------------------
    logic               scanner_busy;
    logic               scanner_done;
    logic               scanner_result_valid;
    logic               scanner_result_ready;
    logic signed [31:0] scanner_result_data;
    logic [9:0]         scanner_result_addr;

    // Output Buffer luon san sang tiep nhan moi ket qua ghi moi chu ky
    assign scanner_result_ready = 1'b1;

    // ------------------------------------------------------------------------
    // Khoi tao conv2d_raster_scanner (Stage 4)
    // Chua Input Buffer (1024x8), Weight Buffer (9x8), Reader & Datapath Dot9
    // ------------------------------------------------------------------------
    conv2d_raster_scanner #(
        .IMG_WIDTH   (IMG_WIDTH),
        .IMG_HEIGHT  (IMG_HEIGHT),
        .KERNEL_SIZE (KERNEL_SIZE),
        .STRIDE      (STRIDE),
        .PADDING     (PADDING)
    ) u_raster_scanner (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .busy         (scanner_busy),
        .done         (scanner_done),
        .ibuf_wr_en   (ibuf_wr_en),
        .ibuf_wr_addr (ibuf_wr_addr),
        .ibuf_wr_data (ibuf_wr_data),
        .wbuf_wr_en   (wbuf_wr_en),
        .wbuf_wr_addr (wbuf_wr_addr),
        .wbuf_wr_data (wbuf_wr_data),
        .result_valid (scanner_result_valid),
        .result_ready (scanner_result_ready),
        .result_data  (scanner_result_data),
        .result_addr  (scanner_result_addr)
    );

    // ------------------------------------------------------------------------
    // Khoi tao output_buffer (Stage 5)
    // Luu tru 900 gia tri signed INT32 (28,800 bits), suy luan Block RAM
    // ------------------------------------------------------------------------
    output_buffer #(
        .DATA_WIDTH (32),
        .DEPTH      (TOTAL_OUTPUTS),
        .ADDR_WIDTH (ADDR_WIDTH),
        .RAM_STYLE  ("block")
    ) u_output_buffer (
        .clk     (clk),
        .wr_en   (scanner_result_valid && scanner_result_ready),
        .wr_addr (scanner_result_addr),
        .wr_data (scanner_result_data),
        .rd_addr (obuf_rd_addr),
        .rd_data (obuf_rd_data)
    );

    // ------------------------------------------------------------------------
    // Tin hieu trang thai toan cuc cua Accelerator
    // ------------------------------------------------------------------------
    // busy: Tich cuc trong suot qua trinh tinh toan tu start cho toi khi ghi xong
    assign busy = scanner_busy;

    // done: Xung 1 chu ky bao toan bo 900 ket qua da duoc ghi an toan vao Output Buffer
    assign done = scanner_done;

endmodule

