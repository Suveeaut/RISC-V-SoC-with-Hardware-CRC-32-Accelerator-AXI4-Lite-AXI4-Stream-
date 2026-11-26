`timescale 1ns / 1ps

module uart_transceiver #(
    parameter int CLK_FREQ      = 100_000_000,
    parameter int BAUD_RATE     = 115_200,
    parameter int FIFO_DEPTH    = 16,
    parameter int AFULL_THRESH  = FIFO_DEPTH - 2,
    parameter int AEMPTY_THRESH = 2
)(
    input  logic       clk,
    input  logic       rst,

    // Serial UART physical pins
    input  logic       rx,
    output logic       tx,

    // AXI4-Stream Slave TX interface (data written into TX FIFO -> uart_tx)
    input  logic [7:0] s_axis_tx_data,
    input  logic       s_axis_tx_valid,
    output logic       s_axis_tx_ready,

    // AXI4-Stream Master RX interface (data from uart_rx -> RX FIFO -> read out)
    output logic [7:0] m_axis_rx_data,
    output logic       m_axis_rx_valid,
    input  logic       m_axis_rx_ready,

    // TX and RX FIFO status flags for monitoring / SoC control
    output logic       tx_fifo_full,
    output logic       tx_fifo_empty,
    output logic       tx_fifo_almost_full,
    output logic       tx_fifo_almost_empty,

    output logic       rx_fifo_full,
    output logic       rx_fifo_empty,
    output logic       rx_fifo_almost_full,
    output logic       rx_fifo_almost_empty
);

    // Internal AXI4-Stream wires connecting TX FIFO to uart_tx
    logic [7:0] tx_fifo_to_uart_data;
    logic       tx_fifo_to_uart_valid;
    logic       tx_fifo_to_uart_ready;

    // Internal AXI4-Stream wires connecting uart_rx to RX FIFO
    logic [7:0] uart_to_rx_fifo_data;
    logic       uart_to_rx_fifo_valid;
    logic       uart_to_rx_fifo_ready;

    // TX FIFO: buffers data from upstream master before serializing
    axis_fifo #(
        .DATA_WIDTH   (8),
        .DEPTH        (FIFO_DEPTH),
        .AFULL_THRESH (AFULL_THRESH),
        .AEMPTY_THRESH(AEMPTY_THRESH)
    ) u_tx_fifo (
        .clk          (clk),
        .rst          (rst),
        .s_axis_data  (s_axis_tx_data),
        .s_axis_valid (s_axis_tx_valid),
        .s_axis_ready (s_axis_tx_ready),
        .m_axis_data  (tx_fifo_to_uart_data),
        .m_axis_valid (tx_fifo_to_uart_valid),
        .m_axis_ready (tx_fifo_to_uart_ready),
        .full         (tx_fifo_full),
        .empty        (tx_fifo_empty),
        .almost_full  (tx_fifo_almost_full),
        .almost_empty (tx_fifo_almost_empty)
    );

    // UART Transmitter: consumes AXI4-Stream beats from TX FIFO
    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_tx (
        .clk         (clk),
        .rst         (rst),
        .s_axis_data (tx_fifo_to_uart_data),
        .s_axis_valid(tx_fifo_to_uart_valid),
        .s_axis_ready(tx_fifo_to_uart_ready),
        .tx          (tx)
    );

    // UART Receiver: produces AXI4-Stream beats into RX FIFO
    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_rx (
        .clk         (clk),
        .rst         (rst),
        .rx          (rx),
        .m_axis_data (uart_to_rx_fifo_data),
        .m_axis_valid(uart_to_rx_fifo_valid),
        .m_axis_ready(uart_to_rx_fifo_ready)
    );

    // RX FIFO: buffers received UART bytes under downstream backpressure
    axis_fifo #(
        .DATA_WIDTH   (8),
        .DEPTH        (FIFO_DEPTH),
        .AFULL_THRESH (AFULL_THRESH),
        .AEMPTY_THRESH(AEMPTY_THRESH)
    ) u_rx_fifo (
        .clk          (clk),
        .rst          (rst),
        .s_axis_data  (uart_to_rx_fifo_data),
        .s_axis_valid (uart_to_rx_fifo_valid),
        .s_axis_ready (uart_to_rx_fifo_ready),
        .m_axis_data  (m_axis_rx_data),
        .m_axis_valid (m_axis_rx_valid),
        .m_axis_ready (m_axis_rx_ready),
        .full         (rx_fifo_full),
        .empty        (rx_fifo_empty),
        .almost_full  (rx_fifo_almost_full),
        .almost_empty (rx_fifo_almost_empty)
    );

endmodule
