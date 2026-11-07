// ============================================================================
// Module Name: soc_ram
// Description: Unified Program & Data Memory (16 KiB Block RAM) with Byte Enables
// Target:      PicoRV32 RISC-V SoC (Stage 6)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module soc_ram #(
    parameter int    WORDS     = 4096, // 4096 x 4 bytes = 16 KiB
    parameter string INIT_FILE = "firmware.hex" // Duong dan file .hex khoi tao chuong trinh
) (
    input  logic                    clk,
    input  logic                    rst,

    // Giao tiep PicoRV32 Memory Native Bus
    input  logic                    mem_valid,
    output logic                    mem_ready,
    input  logic [31:0]             mem_addr,
    input  logic [31:0]             mem_wdata,
    input  logic [3:0]              mem_wstrb,
    output logic [31:0]             mem_rdata
);

    // Dia chi tu (Word Address 32-bit)
    wire [11:0] word_addr = mem_addr[13:2];

    // Mang nho 4096 tu 32-bit, suy luan Block RAM
    (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];

    logic        ready_q;
    logic [31:0] rdata_q;

    // Khoi tao du lieu RAM tu file hex neu co chi dinh
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // Ghi va doc dong bo theo byte enable (1-wait-state BRAM)
    always_ff @(posedge clk) begin
        if (rst) begin
            ready_q <= 1'b0;
            rdata_q <= 32'd0;
        end else begin
            ready_q <= 1'b0;

            if (mem_valid && !ready_q) begin
                ready_q <= 1'b1;

                // Ghi theo byte enable
                if (mem_wstrb[0]) mem[word_addr][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) mem[word_addr][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) mem[word_addr][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) mem[word_addr][31:24] <= mem_wdata[31:24];

                // Doc dong bo
                rdata_q <= mem[word_addr];
            end
        end
    end

    assign mem_ready = ready_q;
    assign mem_rdata = rdata_q;

endmodule

