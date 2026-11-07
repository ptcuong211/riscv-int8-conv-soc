// ============================================================================
// Module Name: output_buffer
// Description: Output Buffer (900 x 32-bit signed INT32) with Synchronous Read
// Target:      RISC-V INT8 Convolution Accelerator (Stage 5)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module output_buffer #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 900,
    parameter int ADDR_WIDTH = 10,
    parameter     RAM_STYLE  = "block"
) (
    input  logic                          clk,

    // Cong ghi dong bo (Write Port) - Nhan du lieu tu conv2d_raster_scanner
    input  logic                          wr_en,
    input  logic [ADDR_WIDTH-1:0]         wr_addr,
    input  logic signed [DATA_WIDTH-1:0]  wr_data,

    // Cong doc dong bo (Read Port) - Cho phep doc ket qua tu he thong ngoai / CPU
    // Do tre doc: 1 chu ky clock (1-Cycle Synchronous Read Latency)
    input  logic [ADDR_WIDTH-1:0]         rd_addr,
    output logic signed [DATA_WIDTH-1:0]  rd_data
);

    // Thuoc tinh huong dan trinh tong hop Vivado suy luan (infer) Block RAM
    (* ram_style = RAM_STYLE *) logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Ghi va doc dong bo theo suon duong xung nhip
    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
        rd_data <= mem[rd_addr];
    end

endmodule

