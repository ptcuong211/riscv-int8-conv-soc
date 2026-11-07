// ============================================================================
// Module Name: soc_top
// Description: Complete RISC-V SoC Top-Level with PicoRV32 & INT8 Conv Accelerator
// Target:      AMD/Xilinx Artix-7 xc7a35tcpg236-1 (Stage 6)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module soc_top #(
    parameter string FIRMWARE_HEX = "firmware.hex" // Duong dan toi file chuong trinh khoi tao RAM
) (
    input  logic                    clk,
    input  logic                    rst,        // Reset dong bo, active-high

    // Tin hieu giam sat he thong
    output logic                    trap,       // Bao CPU roi vao trang thai trap
    output logic [31:0]             debug_out,  // Gia tri thanh ghi Debug (0xCAFE0001 = PASS)
    output logic                    accel_busy, // Trang thai ban cua Accelerator
    output logic                    accel_done  // Xung bao hoan tat cua Accelerator
);

    // ------------------------------------------------------------------------
    // Chuyen doi cuc tinh Reset cho PicoRV32 (Active-Low)
    // ------------------------------------------------------------------------
    wire cpu_resetn = ~rst;

    // ------------------------------------------------------------------------
    // Tin hieu PicoRV32 Native Memory Bus
    // ------------------------------------------------------------------------
    wire        cpu_mem_valid;
    wire        cpu_mem_instr;
    logic       cpu_mem_ready;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [ 3:0] cpu_mem_wstrb;
    logic [31:0] cpu_mem_rdata;

    // ------------------------------------------------------------------------
    // Tin hieu phan vung dia chi (Address Decoder)
    // Vung 0x0000_0000 - 0x0FFF_FFFF : RAM (16 KiB)
    // Vung 0x1000_0000 - 0x1FFF_FFFF : Accelerator MMIO
    // Vung 0x2000_0000 - 0x2FFF_FFFF : Debug Register
    // ------------------------------------------------------------------------
    wire is_ram_addr     = (cpu_mem_addr[31:28] == 4'h0);
    wire is_mmio_addr    = (cpu_mem_addr[31:28] == 4'h1);
    wire is_debug_addr   = (cpu_mem_addr[31:28] == 4'h2);
    wire is_invalid_addr = (!is_ram_addr && !is_mmio_addr && !is_debug_addr);

    // Valid toi tung ngoai vi
    wire ram_valid     = cpu_mem_valid && is_ram_addr;
    wire mmio_valid    = cpu_mem_valid && is_mmio_addr;
    wire debug_valid   = cpu_mem_valid && is_debug_addr;
    wire invalid_valid = cpu_mem_valid && is_invalid_addr;

    // Ready tu tung ngoai vi
    wire        ram_ready;
    wire [31:0] ram_rdata;

    wire        mmio_ready;
    wire [31:0] mmio_rdata;

    logic       debug_ready;
    logic [31:0] reg_debug;

    logic       invalid_ready;

    // ------------------------------------------------------------------------
    // Khoi tao PicoRV32 Core (RV32I)
    // ------------------------------------------------------------------------
    picorv32 #(
        .ENABLE_COUNTERS     (1),
        .ENABLE_COUNTERS64   (0),
        .ENABLE_REGS_16_31   (1),
        .ENABLE_REGS_DUALPORT(1),
        .LATCHED_MEM_RDATA   (0),
        .TWO_STAGE_SHIFT     (1),
        .BARREL_SHIFTER      (1),
        .TWO_CYCLE_COMPARE   (0),
        .TWO_CYCLE_ALU       (0),
        .COMPRESSED_ISA      (0),
        .CATCH_MISALIGN      (1),
        .CATCH_ILLINSN       (1),
        .ENABLE_PCPI         (0),
        .ENABLE_MUL          (0),
        .ENABLE_FAST_MUL     (0),
        .ENABLE_DIV          (0),
        .ENABLE_IRQ          (0),
        .ENABLE_TRACE        (0),
        .REGS_INIT_ZERO      (1),
        .PROGADDR_RESET      (32'h0000_0000),
        .STACKADDR           (32'h0000_3FFC) // Dinh stack tai cuoi RAM 16 KiB
    ) u_cpu (
        .clk       (clk),
        .resetn    (cpu_resetn),
        .trap      (trap),
        .mem_valid (cpu_mem_valid),
        .mem_instr (cpu_mem_instr),
        .mem_ready (cpu_mem_ready),
        .mem_addr  (cpu_mem_addr),
        .mem_wdata (cpu_mem_wdata),
        .mem_wstrb (cpu_mem_wstrb),
        .mem_rdata (cpu_mem_rdata)
    );

    // ------------------------------------------------------------------------
    // Khoi tao Unified RAM (16 KiB - Instructions & Data)
    // ------------------------------------------------------------------------
    soc_ram #(
        .WORDS     (4096),
        .INIT_FILE (FIRMWARE_HEX)
    ) u_ram (
        .clk       (clk),
        .rst       (rst),
        .mem_valid (ram_valid),
        .mem_ready (ram_ready),
        .mem_addr  (cpu_mem_addr),
        .mem_wdata (cpu_mem_wdata),
        .mem_wstrb (cpu_mem_wstrb),
        .mem_rdata (ram_rdata)
    );

    // ------------------------------------------------------------------------
    // Tin hieu ket noi giua Accelerator MMIO va Accelerator Top
    // ------------------------------------------------------------------------
    logic               accel_start_wire;
    logic               accel_busy_wire;
    logic               accel_done_wire;

    logic               ibuf_wr_en_wire;
    logic [9:0]         ibuf_wr_addr_wire;
    logic signed [7:0]  ibuf_wr_data_wire;

    logic               wbuf_wr_en_wire;
    logic [3:0]         wbuf_wr_addr_wire;
    logic signed [7:0]  wbuf_wr_data_wire;

    logic [9:0]         obuf_rd_addr_wire;
    logic signed [31:0] obuf_rd_data_wire;

    assign accel_busy = accel_busy_wire;
    assign accel_done = accel_done_wire;

    // ------------------------------------------------------------------------
    // Khoi tao Accelerator MMIO Controller (Phan vung 0x1000_0000)
    // ------------------------------------------------------------------------
    accelerator_mmio u_accel_mmio (
        .clk           (clk),
        .rst           (rst),
        .mmio_valid    (mmio_valid),
        .mmio_ready    (mmio_ready),
        .mmio_addr     (cpu_mem_addr),
        .mmio_wdata    (cpu_mem_wdata),
        .mmio_wstrb    (cpu_mem_wstrb),
        .mmio_rdata    (mmio_rdata),
        .accel_start   (accel_start_wire),
        .accel_busy    (accel_busy_wire),
        .accel_done    (accel_done_wire),
        .ibuf_wr_en    (ibuf_wr_en_wire),
        .ibuf_wr_addr  (ibuf_wr_addr_wire),
        .ibuf_wr_data  (ibuf_wr_data_wire),
        .wbuf_wr_en    (wbuf_wr_en_wire),
        .wbuf_wr_addr  (wbuf_wr_addr_wire),
        .wbuf_wr_data  (wbuf_wr_data_wire),
        .obuf_rd_addr  (obuf_rd_addr_wire),
        .obuf_rd_data  (obuf_rd_data_wire)
    );

    // ------------------------------------------------------------------------
    // Khoi tao Convolution Accelerator Top (Stage 5)
    // ------------------------------------------------------------------------
    conv_accelerator_top #(
        .IMG_WIDTH   (32),
        .IMG_HEIGHT  (32),
        .KERNEL_SIZE (3),
        .STRIDE      (1),
        .PADDING     (0)
    ) u_accelerator (
        .clk          (clk),
        .rst          (rst),
        .start        (accel_start_wire),
        .busy         (accel_busy_wire),
        .done         (accel_done_wire),
        .ibuf_wr_en   (ibuf_wr_en_wire),
        .ibuf_wr_addr (ibuf_wr_addr_wire),
        .ibuf_wr_data (ibuf_wr_data_wire),
        .wbuf_wr_en   (wbuf_wr_en_wire),
        .wbuf_wr_addr (wbuf_wr_addr_wire),
        .wbuf_wr_data (wbuf_wr_data_wire),
        .obuf_rd_addr (obuf_rd_addr_wire),
        .obuf_rd_data (obuf_rd_data_wire)
    );

    // ------------------------------------------------------------------------
    // Thanh ghi Debug (Phan vung 0x2000_0000)
    // Cho phep CPU ghi trang thai ket qua (0xCAFE0001 = PASS, 0xDEADxxxx = FAIL)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            reg_debug   <= 32'd0;
            debug_ready <= 1'b0;
        end else begin
            debug_ready <= 1'b0;
            if (debug_valid && !debug_ready) begin
                debug_ready <= 1'b1;
                if (|cpu_mem_wstrb) begin
                    reg_debug <= cpu_mem_wdata;
                end
            end
        end
    end

    assign debug_out = reg_debug;

    // ------------------------------------------------------------------------
    // Xu ly dia chi khong hop le (Bao ve chong treo bus)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            invalid_ready <= 1'b0;
        end else begin
            invalid_ready <= 1'b0;
            if (invalid_valid && !invalid_ready) begin
                invalid_ready <= 1'b1; // Tra ve ready de CPU khong bi treo vo han
            end
        end
    end

    // ------------------------------------------------------------------------
    // Ghep kenh phan hoi du lieu va tin hieu ready cho CPU
    // ------------------------------------------------------------------------
    assign cpu_mem_ready = ram_ready | mmio_ready | debug_ready | invalid_ready;

    always_comb begin
        if (is_ram_addr) begin
            cpu_mem_rdata = ram_rdata;
        end else if (is_mmio_addr) begin
            cpu_mem_rdata = mmio_rdata;
        end else if (is_debug_addr) begin
            cpu_mem_rdata = reg_debug;
        end else begin
            cpu_mem_rdata = 32'hDEAD_DEAD; // Gia tri doc khi dia chi khong hop le
        end
    end

endmodule

