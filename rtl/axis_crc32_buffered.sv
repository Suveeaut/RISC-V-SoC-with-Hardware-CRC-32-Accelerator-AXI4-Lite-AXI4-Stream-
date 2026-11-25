`timescale 1ns / 1ps

module axis_crc32_buffered #(
    parameter int          IN_FIFO_DEPTH  = 32,
    parameter int          OUT_FIFO_DEPTH = 16,
    parameter logic [31:0] POLY           = 32'hEDB8_8320,
    parameter logic [31:0] INIT_CRC       = 32'hFFFF_FFFF,
    parameter logic [31:0] FINAL_XOR      = 32'hFFFF_FFFF
)(
    input  logic        clk,
    input  logic        rst,

    // Upstream AXI4-Stream byte stream with packet boundary (tlast)
    input  logic [7:0]  s_axis_in_tdata,
    input  logic        s_axis_in_tvalid,
    output logic        s_axis_in_tready,
    input  logic        s_axis_in_tlast,

    // Downstream AXI4-Stream 32-bit CRC-32 result stream
    output logic [31:0] m_axis_out_tdata,
    output logic        m_axis_out_tvalid,
    input  logic        m_axis_out_tready,

    // FIFO status flags
    output logic        in_fifo_full,
    output logic        in_fifo_empty,
    output logic        in_fifo_almost_full,
    output logic        in_fifo_almost_empty,

    output logic        out_fifo_full,
    output logic        out_fifo_empty,
    output logic        out_fifo_almost_full,
    output logic        out_fifo_almost_empty
);

    logic [8:0]  in_fifo_s_data;
    logic [8:0]  in_fifo_m_data;
    logic        in_fifo_m_valid;
    logic        in_fifo_m_ready;

    logic [7:0]  crc_s_tdata;
    logic        crc_s_tlast;

    logic [31:0] crc_m_tdata;
    logic        crc_m_tvalid;
    logic        crc_m_tready;

    assign in_fifo_s_data = {s_axis_in_tlast, s_axis_in_tdata};
    assign crc_s_tlast    = in_fifo_m_data[8];
    assign crc_s_tdata    = in_fifo_m_data[7:0];

    // Stage 1: Input FIFO (buffers byte + tlast)
    axis_fifo #(
        .DATA_WIDTH   (9),
        .DEPTH        (IN_FIFO_DEPTH),
        .AFULL_THRESH (IN_FIFO_DEPTH - 2),
        .AEMPTY_THRESH(2)
    ) u_in_fifo (
        .clk          (clk),
        .rst          (rst),
        .s_axis_data  (in_fifo_s_data),
        .s_axis_valid (s_axis_in_tvalid),
        .s_axis_ready (s_axis_in_tready),
        .m_axis_data  (in_fifo_m_data),
        .m_axis_valid (in_fifo_m_valid),
        .m_axis_ready (in_fifo_m_ready),
        .full         (in_fifo_full),
        .empty        (in_fifo_empty),
        .almost_full  (in_fifo_almost_full),
        .almost_empty (in_fifo_almost_empty)
    );

    // Stage 2: CRC-32 Accelerator Core
    axis_crc32 #(
        .POLY     (POLY),
        .INIT_CRC (INIT_CRC),
        .FINAL_XOR(FINAL_XOR)
    ) u_crc32 (
        .clk           (clk),
        .rst           (rst),
        .s_axis_tdata  (crc_s_tdata),
        .s_axis_tvalid (in_fifo_m_valid),
        .s_axis_tready (in_fifo_m_ready),
        .s_axis_tlast  (crc_s_tlast),
        .m_axis_tdata  (crc_m_tdata),
        .m_axis_tvalid (crc_m_tvalid),
        .m_axis_tready (crc_m_tready)
    );

    // Stage 3: Output FIFO (buffers 32-bit CRC-32 results)
    axis_fifo #(
        .DATA_WIDTH   (32),
        .DEPTH        (OUT_FIFO_DEPTH),
        .AFULL_THRESH (OUT_FIFO_DEPTH - 2),
        .AEMPTY_THRESH(2)
    ) u_out_fifo (
        .clk          (clk),
        .rst          (rst),
        .s_axis_data  (crc_m_tdata),
        .s_axis_valid (crc_m_tvalid),
        .s_axis_ready (crc_m_tready),
        .m_axis_data  (m_axis_out_tdata),
        .m_axis_valid (m_axis_out_tvalid),
        .m_axis_ready (m_axis_out_tready),
        .full         (out_fifo_full),
        .empty        (out_fifo_empty),
        .almost_full  (out_fifo_almost_full),
        .almost_empty (out_fifo_almost_empty)
    );

endmodule
