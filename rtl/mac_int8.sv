// ============================================================================
// Module Name: mac_int8
// Description: Multiply-Accumulate (MAC) Unit for Signed INT8 Operands
// Target:      RISC-V INT8 Convolution Accelerator (Stage 1)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module mac_int8 (
    input  logic               clk,    // System clock
    input  logic               rst,    // Synchronous reset, active-high
    input  logic               clear,  // Synchronous accumulator clear, active-high
    input  logic               valid,  // Input operands valid strobe
    input  logic signed [7:0]  x,      // Signed 8-bit input (activation/pixel)
    input  logic signed [7:0]  w,      // Signed 8-bit input (weight/kernel)
    output logic signed [31:0] acc     // Signed 32-bit accumulator output
);

    // Tín hiệu nội bộ cho tích 16-bit và tích sau khi mở rộng dấu (sign extension)
    logic signed [15:0] product;
    logic signed [31:0] product_ext;

    // ------------------------------------------------------------------------
    // Khối nhân tổ hợp signed INT8: x * w -> product (16-bit)
    // ------------------------------------------------------------------------
    int8_multiplier u_multiplier (
        .x       (x),
        .w       (w),
        .product (product)
    );

    // ------------------------------------------------------------------------
    // Mở rộng dấu (Sign Extension) từ 16-bit sang 32-bit
    // Giữ nguyên giá trị số học bù 2 của tích khi đưa vào bộ cộng 32-bit.
    // Bit dấu product[15] được nhân bản lên 16 bit cao.
    // ------------------------------------------------------------------------
    assign product_ext = {{16{product[15]}}, product};

    // ------------------------------------------------------------------------
    // Thanh ghi tích lũy 32-bit (Accumulator Register)
    // Thứ tự ưu tiên điều khiển: rst > clear > valid
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset đồng bộ mức cao: đưa acc về 0
            acc <= 32'sd0;
        end else if (clear) begin
            // Clear đồng bộ mức cao: xóa acc về 0
            // Nếu clear và valid cùng bằng 1: ưu tiên clear, không nhận dữ liệu
            acc <= 32'sd0;
        end else if (valid) begin
            // Khi dữ liệu hợp lệ: cộng dồn tích mới vào accumulator
            // Phép cộng bù hai wrap tự nhiên nếu vượt giới hạn 32-bit
            acc <= acc + product_ext;
        end
        // Ngầm định khi valid == 0 và rst/clear == 0: acc giữ nguyên giá trị
    end

endmodule
