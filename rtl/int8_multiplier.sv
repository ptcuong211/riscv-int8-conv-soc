// ============================================================================
// Module Name: int8_multiplier
// Description: Signed 8-bit Combinational Multiplier
// Target:      RISC-V INT8 Convolution Accelerator (Stage 1)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module int8_multiplier (
    input  logic signed [7:0]  x,       // Signed 8-bit input operand (activation/pixel)
    input  logic signed [7:0]  w,       // Signed 8-bit input operand (weight/kernel)
    output logic signed [15:0] product  // Signed 16-bit product
);

    // Thuần tổ hợp: nhân 2 số bù 2 8-bit tạo tích 16-bit đầy đủ.
    // Khoảng giá trị:
    // Min = -128 * 127  = -16,256 (16'hC080)
    // Max = -128 * -128 = +16,384 (16'h4000)
    // Kiểu signed 16-bit biểu diễn từ -32,768 đến +32,767 nên không xảy ra tràn bit.
    assign product = x * w;

endmodule
