// ============================================================================
// Module Name: ram_sync_read
// Description: Synchronous Read RAM with Write Port (Infers FPGA Block RAM / LUTRAM)
// Target:      RISC-V INT8 Convolution Accelerator (Stage 3)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module ram_sync_read #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 10,
    parameter int DEPTH      = 1024,
    parameter     RAM_STYLE  = "block" // "block" cho BRAM, "distributed" cho LUTRAM
) (
    input  logic                    clk,
    input  logic                    wr_en,
    input  logic [ADDR_WIDTH-1:0]   wr_addr,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    input  logic [ADDR_WIDTH-1:0]   rd_addr,
    output logic [DATA_WIDTH-1:0]   rd_data
);

    // Thuoc tinh chi dinh phong cach tong hop RAM cho Vivado Synthesis
    (* ram_style = RAM_STYLE *) logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Doc dong bo co do tre doc 1 chu ky clock (1-Cycle Read Latency)
    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
        rd_data <= mem[rd_addr];
    end

endmodule
