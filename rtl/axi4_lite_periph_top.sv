`timescale 1ns / 1ps

module axi4_lite_periph_top #(
    parameter int          ADDR_WIDTH     = 8,
    parameter int          IN_FIFO_DEPTH  = 32,
    parameter int          OUT_FIFO_DEPTH = 16,
    parameter logic [31:0] POLY           = 32'hEDB8_8320,
    parameter logic [31:0] INIT_CRC       = 32'hFFFF_FFFF,
    parameter logic [31:0] FINAL_XOR      = 32'hFFFF_FFFF
)(
    input  logic                  clk,
    input  logic                  rst,

    // AXI4-Lite Write Address Channel
    input  logic [ADDR_WIDTH-1:0] s_axil_awaddr,
    input  logic                  s_axil_awvalid,
    output logic                  s_axil_awready,

    // AXI4-Lite Write Data Channel
    input  logic [31:0]           s_axil_wdata,
    input  logic [3:0]            s_axil_wstrb,
    input  logic                  s_axil_wvalid,
    output logic                  s_axil_wready,

    // AXI4-Lite Write Response Channel
    output logic [1:0]            s_axil_bresp,
    output logic                  s_axil_bvalid,
    input  logic                  s_axil_bready,

    // AXI4-Lite Read Address Channel
    input  logic [ADDR_WIDTH-1:0] s_axil_araddr,
    input  logic                  s_axil_arvalid,
    output logic                  s_axil_arready,

    // AXI4-Lite Read Data Channel
    output logic [31:0]           s_axil_rdata,
    output logic [1:0]            s_axil_rresp,
    output logic                  s_axil_rvalid,
    input  logic                  s_axil_rready,

    // Optional external AXI4-Stream output
    output logic [31:0]           crc_m_axis_tdata,
    output logic                  crc_m_axis_tvalid,
    input  logic                  crc_m_axis_tready,

    // UART physical pins
    input  logic                  uart_rx,
    output logic                  uart_tx
);

    localparam logic [ADDR_WIDTH-1:0] ADDR_CRC_DATA_IN = 8'h00;
    localparam logic [ADDR_WIDTH-1:0] ADDR_CRC_CTRL    = 8'h04;
    localparam logic [ADDR_WIDTH-1:0] ADDR_CRC_RESULT  = 8'h08;
    localparam logic [ADDR_WIDTH-1:0] ADDR_CRC_STATUS  = 8'h0C;
    localparam logic [ADDR_WIDTH-1:0] ADDR_UART_TX     = 8'h10;
    localparam logic [ADDR_WIDTH-1:0] ADDR_UART_RX     = 8'h14;
    localparam logic [ADDR_WIDTH-1:0] ADDR_UART_STATUS = 8'h18;

    logic                  aw_en;
    logic [ADDR_WIDTH-1:0] awaddr_reg;
    logic [ADDR_WIDTH-1:0] araddr_reg;

    logic                  last_arm_reg;
    logic                  soft_clr_pulse;
    logic                  sys_rst;

    logic [7:0]            crc_s_tdata;
    logic                  crc_s_tvalid;
    logic                  crc_s_tready;
    logic                  crc_s_tlast;

    logic [31:0]           crc_out_tdata_int;
    logic                  crc_out_tvalid_int;
    logic                  crc_out_tready_int;

    logic                  in_fifo_full, in_fifo_empty, in_fifo_almost_full, in_fifo_almost_empty;
    logic                  out_fifo_full, out_fifo_empty, out_fifo_almost_full, out_fifo_almost_empty;

    logic [7:0]            uart_tx_tdata;
    logic                  uart_tx_tvalid;
    logic                  uart_tx_tready;

    logic [7:0]            uart_rx_tdata;
    logic                  uart_rx_tvalid;
    logic                  uart_rx_tready;

    logic [31:0]           latched_crc_result;

    assign sys_rst = rst || soft_clr_pulse;

    assign crc_m_axis_tdata  = crc_out_tdata_int;
    assign crc_m_axis_tvalid = crc_out_tvalid_int;

    // Write channel logic
    always_ff @(posedge clk) begin
        if (rst) begin
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            aw_en          <= 1'b1;
            awaddr_reg     <= '0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= 2'b00;
            soft_clr_pulse <= 1'b0;
            last_arm_reg   <= 1'b0;
            crc_s_tdata    <= 8'h00;
            crc_s_tvalid   <= 1'b0;
            crc_s_tlast    <= 1'b0;
            uart_tx_tdata  <= 8'h00;
            uart_tx_tvalid <= 1'b0;
        end else begin
            soft_clr_pulse <= 1'b0;

            if (crc_s_tvalid && crc_s_tready) begin
                crc_s_tvalid <= 1'b0;
                crc_s_tlast  <= 1'b0;
            end
            if (uart_tx_tvalid && uart_tx_tready) begin
                uart_tx_tvalid <= 1'b0;
            end

            if (!s_axil_awready && s_axil_awvalid && s_axil_wvalid && aw_en) begin
                s_axil_awready <= 1'b1;
                aw_en          <= 1'b0;
                awaddr_reg     <= s_axil_awaddr;
            end else begin
                s_axil_awready <= 1'b0;
                if (s_axil_bvalid && s_axil_bready) begin
                    aw_en <= 1'b1;
                end
            end

            if (!s_axil_wready && s_axil_wvalid && s_axil_awvalid && aw_en) begin
                s_axil_wready <= 1'b1;
            end else begin
                s_axil_wready <= 1'b0;
            end

            if (s_axil_awready && s_axil_wready && s_axil_awvalid && s_axil_wvalid) begin
                case (awaddr_reg)
                    ADDR_CRC_DATA_IN: begin
                        if (s_axil_wstrb[0]) begin
                            crc_s_tdata  <= s_axil_wdata[7:0];
                            crc_s_tlast  <= last_arm_reg;
                            crc_s_tvalid <= 1'b1;
                            last_arm_reg <= 1'b0;
                        end
                    end

                    ADDR_CRC_CTRL: begin
                        if (s_axil_wstrb[0]) begin
                            last_arm_reg   <= s_axil_wdata[0];
                            soft_clr_pulse <= s_axil_wdata[1];
                        end
                    end

                    ADDR_UART_TX: begin
                        if (s_axil_wstrb[0]) begin
                            uart_tx_tdata  <= s_axil_wdata[7:0];
                            uart_tx_tvalid <= 1'b1;
                        end
                    end

                    default: ;
                endcase
            end

            if (s_axil_awready && s_axil_wready && !s_axil_bvalid) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= 2'b00;
            end else if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    // Latch CRC result whenever popped
    always_ff @(posedge clk) begin
        if (sys_rst) begin
            latched_crc_result <= 32'h0000_0000;
        end else if (crc_out_tvalid_int && crc_out_tready_int) begin
            latched_crc_result <= crc_out_tdata_int;
        end
    end

    // Read channel logic
    always_ff @(posedge clk) begin
        if (rst) begin
            s_axil_arready     <= 1'b0;
            araddr_reg         <= '0;
            s_axil_rvalid      <= 1'b0;
            s_axil_rresp       <= 2'b00;
            s_axil_rdata       <= 32'h0;
            crc_out_tready_int <= 1'b0;
            uart_rx_tready     <= 1'b0;
        end else begin
            crc_out_tready_int <= 1'b0;
            uart_rx_tready     <= 1'b0;

            if (!s_axil_arready && s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                araddr_reg     <= s_axil_araddr;
            end else begin
                s_axil_arready <= 1'b0;
            end

            if (s_axil_arready && s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_rvalid <= 1'b1;
                s_axil_rresp  <= 2'b00;

                case (araddr_reg)
                    ADDR_CRC_CTRL: begin
                        s_axil_rdata <= {30'h0, soft_clr_pulse, last_arm_reg};
                    end

                    ADDR_CRC_RESULT: begin
                        if (crc_out_tvalid_int) begin
                            s_axil_rdata       <= crc_out_tdata_int;
                            crc_out_tready_int <= 1'b1;
                        end else begin
                            s_axil_rdata <= latched_crc_result;
                        end
                    end

                    ADDR_CRC_STATUS: begin
                        s_axil_rdata <= {
                            24'h0,
                            out_fifo_almost_full,
                            out_fifo_full,
                            out_fifo_empty,
                            in_fifo_almost_full,
                            in_fifo_full,
                            in_fifo_empty,
                            crc_s_tready,
                            crc_out_tvalid_int
                        };
                    end

                    ADDR_UART_RX: begin
                        s_axil_rdata <= {24'h0, uart_rx_tdata};
                        if (uart_rx_tvalid) begin
                            uart_rx_tready <= 1'b1;
                        end
                    end

                    ADDR_UART_STATUS: begin
                        s_axil_rdata <= {
                            28'h0,
                            1'b0,
                            1'b0,
                            uart_rx_tvalid,
                            uart_tx_tready
                        };
                    end

                    default: begin
                        s_axil_rdata <= 32'hDEAD_BEEF;
                    end
                endcase
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

    axis_crc32_buffered #(
        .IN_FIFO_DEPTH (IN_FIFO_DEPTH),
        .OUT_FIFO_DEPTH(OUT_FIFO_DEPTH),
        .POLY          (POLY),
        .INIT_CRC      (INIT_CRC),
        .FINAL_XOR     (FINAL_XOR)
    ) u_crc32_subsys (
        .clk                   (clk),
        .rst                   (sys_rst),
        .s_axis_in_tdata       (crc_s_tdata),
        .s_axis_in_tvalid      (crc_s_tvalid),
        .s_axis_in_tready      (crc_s_tready),
        .s_axis_in_tlast       (crc_s_tlast),
        .m_axis_out_tdata      (crc_out_tdata_int),
        .m_axis_out_tvalid     (crc_out_tvalid_int),
        .m_axis_out_tready     (crc_out_tready_int || crc_m_axis_tready),
        .in_fifo_full          (in_fifo_full),
        .in_fifo_empty         (in_fifo_empty),
        .in_fifo_almost_full   (in_fifo_almost_full),
        .in_fifo_almost_empty  (in_fifo_almost_empty),
        .out_fifo_full         (out_fifo_full),
        .out_fifo_empty        (out_fifo_empty),
        .out_fifo_almost_full  (out_fifo_almost_full),
        .out_fifo_almost_empty (out_fifo_almost_empty)
    );

    uart_transceiver u_uart_subsys (
        .clk           (clk),
        .rst           (sys_rst),
        .s_axis_tx_data  (uart_tx_tdata),
        .s_axis_tx_valid (uart_tx_tvalid),
        .s_axis_tx_ready (uart_tx_tready),
        .m_axis_rx_data  (uart_rx_tdata),
        .m_axis_rx_valid (uart_rx_tvalid),
        .m_axis_rx_ready (uart_rx_tready),
        .rx            (uart_rx),
        .tx            (uart_tx)
    );

endmodule
