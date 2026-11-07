// ============================================================================
// Module Name: accelerator_mmio
// Description: MMIO Control & Data Interface for INT8 Convolution Accelerator
// Target:      PicoRV32 RISC-V SoC (Stage 6)
// Author:      RTL Design & Verification Team
// ============================================================================

`timescale 1ns / 1ps

module accelerator_mmio (
    input  logic                    clk,
    input  logic                    rst,

    // Giao tiếp PicoRV32 Native Memory Bus (Phân vùng MMIO: 0x1000_0000 - 0x1000_001F)
    input  logic                    mmio_valid,
    output logic                    mmio_ready,
    input  logic [31:0]             mmio_addr,
    input  logic [31:0]             mmio_wdata,
    input  logic [3:0]              mmio_wstrb,
    output logic [31:0]             mmio_rdata,

    // Giao tiếp điều khiển tới conv_accelerator_top
    output logic                    accel_start,
    input  logic                    accel_busy,
    input  logic                    accel_done,

    // Giao tiếp nạp Input Buffer (1024x8 signed INT8)
    output logic                    ibuf_wr_en,
    output logic [9:0]              ibuf_wr_addr,
    output logic signed [7:0]       ibuf_wr_data,

    // Giao tiếp nạp Weight Buffer (9x8 signed INT8)
    output logic                    wbuf_wr_en,
    output logic [3:0]              wbuf_wr_addr,
    output logic signed [7:0]       wbuf_wr_data,

    // Giao tiếp đọc Output Buffer (900x32 signed INT32)
    output logic [9:0]              obuf_rd_addr,
    input  logic signed [31:0]      obuf_rd_data
);

    // ------------------------------------------------------------------------
    // Định nghĩa Offset thanh ghi MMIO (Byte Offsets)
    // ------------------------------------------------------------------------
    localparam logic [4:0] REG_ACCEL_CTRL   = 5'h00; // 0x1000_0000: W: bit 0 = START
    localparam logic [4:0] REG_ACCEL_STATUS = 5'h04; // 0x1000_0004: R: bit 0 = BUSY, bit 1 = DONE; W: bit 1 = W1C
    localparam logic [4:0] REG_IBUF_ADDR    = 5'h08; // 0x1000_0008: R/W: 0..1023
    localparam logic [4:0] REG_IBUF_DATA    = 5'h0C; // 0x1000_000C: W: Ghi pixel vào Input Buffer
    localparam logic [4:0] REG_WBUF_ADDR    = 5'h10; // 0x1000_0010: R/W: 0..8
    localparam logic [4:0] REG_WBUF_DATA    = 5'h14; // 0x1000_0014: W: Ghi trọng số vào Weight Buffer
    localparam logic [4:0] REG_OBUF_ADDR    = 5'h18; // 0x1000_0018: R/W: 0..899
    localparam logic [4:0] REG_OBUF_DATA    = 5'h1C; // 0x1000_001C: R: Đọc kết quả từ Output Buffer

    // ------------------------------------------------------------------------
    // Các thanh ghi nội bộ MMIO
    // ------------------------------------------------------------------------
    logic [9:0]         reg_ibuf_addr;
    logic signed [7:0]  reg_ibuf_data;
    logic [3:0]         reg_wbuf_addr;
    logic signed [7:0]  reg_wbuf_data;
    logic [9:0]         reg_obuf_addr;
    logic               sticky_done;
    logic               start_pulse;
    logic               ibuf_wr_pulse;
    logic               wbuf_wr_pulse;

    // Phản hồi bus PicoRV32 (1-cycle registered ready)
    logic               ready_q;
    logic [31:0]        rdata_q;

    // Trích xuất 5-bit offset thấp của địa chỉ
    wire [4:0] reg_offset = mmio_addr[4:0];
    wire       is_write   = (|mmio_wstrb);

    // Nối trực tiếp địa chỉ đọc ra Output Buffer
    assign obuf_rd_addr = reg_obuf_addr;

    // ------------------------------------------------------------------------
    // Xử lý ghi thanh ghi và tạo các xung điều khiển
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            reg_ibuf_addr  <= '0;
            reg_ibuf_data  <= '0;
            reg_wbuf_addr  <= '0;
            reg_wbuf_data  <= '0;
            reg_obuf_addr  <= '0;
            sticky_done    <= 1'b0;
            start_pulse    <= 1'b0;
            ibuf_wr_pulse  <= 1'b0;
            wbuf_wr_pulse  <= 1'b0;
            ready_q        <= 1'b0;
            rdata_q        <= 32'd0;
        end else begin
            // Mặc định các xung tích cực 1 chu kỳ sẽ tự xóa
            start_pulse   <= 1'b0;
            ibuf_wr_pulse <= 1'b0;
            wbuf_wr_pulse <= 1'b0;
            ready_q       <= 1'b0;

            // Bắt sự kiện accelerator hoàn thành (done pulse)
            if (accel_done) begin
                sticky_done <= 1'b1;
            end

            // Xử lý giao dịch bus MMIO từ CPU
            if (mmio_valid && !ready_q) begin
                ready_q <= 1'b1; // Báo transaction hoàn tất ở chu kỳ tiếp theo

                if (is_write) begin
                    // Ghi thanh ghi MMIO
                    case (reg_offset)
                        REG_ACCEL_CTRL: begin
                            if (mmio_wdata[0]) begin
                                start_pulse <= 1'b1;
                                sticky_done <= 1'b0; // Khởi động lượt mới thì xóa cờ DONE cũ
                            end
                        end

                        REG_ACCEL_STATUS: begin
                            // Ghi 1 vào bit 1 để xóa cờ sticky DONE (W1C)
                            if (mmio_wdata[1]) begin
                                sticky_done <= 1'b0;
                            end
                        end

                        REG_IBUF_ADDR: begin
                            reg_ibuf_addr <= mmio_wdata[9:0];
                        end

                        REG_IBUF_DATA: begin
                            reg_ibuf_data <= mmio_wdata[7:0];
                            ibuf_wr_pulse <= 1'b1; // Phát xung ghi Input Buffer
                        end

                        REG_WBUF_ADDR: begin
                            reg_wbuf_addr <= mmio_wdata[3:0];
                        end

                        REG_WBUF_DATA: begin
                            reg_wbuf_data <= mmio_wdata[7:0];
                            wbuf_wr_pulse <= 1'b1; // Phát xung ghi Weight Buffer
                        end

                        REG_OBUF_ADDR: begin
                            reg_obuf_addr <= mmio_wdata[9:0];
                        end

                        default: begin
                            // Không thực hiện thao tác nếu offset không xác định
                        end
                    endcase
                end else begin
                    // Đọc thanh ghi MMIO
                    case (reg_offset)
                        REG_ACCEL_CTRL: begin
                            rdata_q <= {31'd0, start_pulse};
                        end

                        REG_ACCEL_STATUS: begin
                            // bit 0 = busy, bit 1 = sticky_done
                            rdata_q <= {30'd0, sticky_done, accel_busy};
                        end

                        REG_IBUF_ADDR: begin
                            rdata_q <= {22'd0, reg_ibuf_addr};
                        end

                        REG_IBUF_DATA: begin
                            rdata_q <= {24'd0, reg_ibuf_data};
                        end

                        REG_WBUF_ADDR: begin
                            rdata_q <= {28'd0, reg_wbuf_addr};
                        end

                        REG_WBUF_DATA: begin
                            rdata_q <= {24'd0, reg_wbuf_data};
                        end

                        REG_OBUF_ADDR: begin
                            rdata_q <= {22'd0, reg_obuf_addr};
                        end

                        REG_OBUF_DATA: begin
                            // Đọc dữ liệu Output Buffer (32-bit signed INT32)
                            rdata_q <= obuf_rd_data;
                        end

                        default: begin
                            rdata_q <= 32'hDEAD_BEEF; // Báo hiệu địa chỉ MMIO không hợp lệ
                        end
                    endcase
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Ngõ ra điều khiển nối tới Accelerator
    // ------------------------------------------------------------------------
    assign accel_start  = start_pulse;
    assign ibuf_wr_en   = ibuf_wr_pulse;
    assign ibuf_wr_addr = reg_ibuf_addr;
    assign ibuf_wr_data = reg_ibuf_data;

    assign wbuf_wr_en   = wbuf_wr_pulse;
    assign wbuf_wr_addr = reg_wbuf_addr;
    assign wbuf_wr_data = reg_wbuf_data;

    // Ngõ ra bus PicoRV32
    assign mmio_ready   = ready_q;
    assign mmio_rdata   = rdata_q;

endmodule

