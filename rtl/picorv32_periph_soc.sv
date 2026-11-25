`timescale 1ns / 1ps

module picorv32_periph_soc #(
    parameter int MEM_WORDS = 1024
)(
    input  logic        clk,
    input  logic        rst_n, // active-low reset for PicoRV32; invert to rst for AXI/FIFO/CRC
    output logic [31:0] crc_m_axis_tdata,
    output logic        crc_m_axis_tvalid,
    input  logic        crc_m_axis_tready,
    input  logic        uart_rx,
    output logic        uart_tx
);

    logic        rst;
    assign rst = ~rst_n;

    // PicoRV32 AXI4-Lite Master wires
    logic        mem_axi_awvalid;
    logic        mem_axi_awready;
    logic [31:0] mem_axi_awaddr;
    logic [2:0]  mem_axi_awprot;

    logic        mem_axi_wvalid;
    logic        mem_axi_wready;
    logic [31:0] mem_axi_wdata;
    logic [3:0]  mem_axi_wstrb;

    logic        mem_axi_bvalid;
    logic        mem_axi_bready;

    logic        mem_axi_arvalid;
    logic        mem_axi_arready;
    logic [31:0] mem_axi_araddr;
    logic [2:0]  mem_axi_arprot;

    logic        mem_axi_rvalid;
    logic        mem_axi_rready;
    logic [31:0] mem_axi_rdata;

    // Address decode: bit[30] == 1 -> Peripheral (0x4000_0000), else SRAM (0x0000_0000)
    wire sel_periph_aw = mem_axi_awaddr[30];
    wire sel_periph_ar = mem_axi_araddr[30];

    // SRAM AXI4-Lite Slave signals
    logic [31:0] ram [0:MEM_WORDS-1];
    logic        ram_awready, ram_wready, ram_bvalid, ram_arready, ram_rvalid;
    logic [31:0] ram_rdata;
    logic [31:0] ram_awaddr_q, ram_araddr_q;

    // Peripheral AXI4-Lite Slave signals
    logic        periph_awready, periph_wready, periph_bvalid, periph_arready, periph_rvalid;
    logic [1:0]  periph_bresp, periph_rresp;
    logic [31:0] periph_rdata;

    // PicoRV32 AXI4-Lite Core (requires picorv32.v added to Design Sources)
    picorv32_axi #(
        .ENABLE_MUL     (0),
        .ENABLE_DIV     (0),
        .PROGADDR_RESET (32'h0000_0000),
        .STACKADDR      (32'h0000_1000)
    ) u_cpu (
        .clk            (clk),
        .resetn         (rst_n),
        .mem_axi_awvalid(mem_axi_awvalid),
        .mem_axi_awready(mem_axi_awready),
        .mem_axi_awaddr (mem_axi_awaddr),
        .mem_axi_awprot (mem_axi_awprot),
        .mem_axi_wvalid (mem_axi_wvalid),
        .mem_axi_wready (mem_axi_wready),
        .mem_axi_wdata  (mem_axi_wdata),
        .mem_axi_wstrb  (mem_axi_wstrb),
        .mem_axi_bvalid (mem_axi_bvalid),
        .mem_axi_bready (mem_axi_bready),
        .mem_axi_arvalid(mem_axi_arvalid),
        .mem_axi_arready(mem_axi_arready),
        .mem_axi_araddr (mem_axi_araddr),
        .mem_axi_arprot (mem_axi_arprot),
        .mem_axi_rvalid (mem_axi_rvalid),
        .mem_axi_rready (mem_axi_rready),
        .mem_axi_rdata  (mem_axi_rdata)
    );

    // Interconnect muxing
    assign mem_axi_awready = sel_periph_aw ? periph_awready : ram_awready;
    assign mem_axi_wready  = sel_periph_aw ? periph_wready  : ram_wready;
    assign mem_axi_bvalid  = sel_periph_aw ? periph_bvalid  : ram_bvalid;
    assign mem_axi_arready = sel_periph_ar ? periph_arready : ram_arready;
    assign mem_axi_rvalid  = sel_periph_ar ? periph_rvalid  : ram_rvalid;
    assign mem_axi_rdata   = sel_periph_ar ? periph_rdata   : ram_rdata;

    // Simple AXI4-Lite SRAM Slave
    always_ff @(posedge clk) begin
        if (rst) begin
            ram_awready  <= 1'b0;
            ram_wready   <= 1'b0;
            ram_bvalid   <= 1'b0;
            ram_arready  <= 1'b0;
            ram_rvalid   <= 1'b0;
            ram_rdata    <= 32'h0;
            ram_awaddr_q <= 32'h0;
            ram_araddr_q <= 32'h0;
        end else begin
            ram_awready <= (!sel_periph_aw && mem_axi_awvalid && mem_axi_wvalid && !ram_awready && !ram_bvalid);
            ram_wready  <= (!sel_periph_aw && mem_axi_awvalid && mem_axi_wvalid && !ram_wready  && !ram_bvalid);

            if (!sel_periph_aw && mem_axi_awvalid && mem_axi_wvalid && !ram_bvalid) begin
                ram_awaddr_q <= mem_axi_awaddr;
                if (mem_axi_wstrb[0]) ram[mem_axi_awaddr[11:2]][7:0]   <= mem_axi_wdata[7:0];
                if (mem_axi_wstrb[1]) ram[mem_axi_awaddr[11:2]][15:8]  <= mem_axi_wdata[15:8];
                if (mem_axi_wstrb[2]) ram[mem_axi_awaddr[11:2]][23:16] <= mem_axi_wdata[23:16];
                if (mem_axi_wstrb[3]) ram[mem_axi_awaddr[11:2]][31:24] <= mem_axi_wdata[31:24];
            end

            if (ram_awready && ram_wready && !ram_bvalid) begin
                ram_bvalid <= 1'b1;
            end else if (ram_bvalid && mem_axi_bready) begin
                ram_bvalid <= 1'b0;
            end

            if (!sel_periph_ar && mem_axi_arvalid && !ram_arready && !ram_rvalid) begin
                ram_arready  <= 1'b1;
                ram_araddr_q <= mem_axi_araddr;
            end else begin
                ram_arready <= 1'b0;
            end

            if (ram_arready && !ram_rvalid) begin
                ram_rvalid <= 1'b1;
                ram_rdata  <= ram[ram_araddr_q[11:2]];
            end else if (ram_rvalid && mem_axi_rready) begin
                ram_rvalid <= 1'b0;
            end
        end
    end

    // Peripheral AXI4-Lite Slave instance
    axi4_lite_periph_top #(
        .ADDR_WIDTH(8)
    ) u_periph (
        .clk               (clk),
        .rst               (rst),
        .s_axil_awaddr     (mem_axi_awaddr[7:0]),
        .s_axil_awvalid    (sel_periph_aw && mem_axi_awvalid),
        .s_axil_awready    (periph_awready),
        .s_axil_wdata      (mem_axi_wdata),
        .s_axil_wstrb      (mem_axi_wstrb),
        .s_axil_wvalid     (sel_periph_aw && mem_axi_wvalid),
        .s_axil_wready     (periph_wready),
        .s_axil_bresp      (periph_bresp),
        .s_axil_bvalid     (periph_bvalid),
        .s_axil_bready     (mem_axi_bready),
        .s_axil_araddr     (mem_axi_araddr[7:0]),
        .s_axil_arvalid    (sel_periph_ar && mem_axi_arvalid),
        .s_axil_arready    (periph_arready),
        .s_axil_rdata      (periph_rdata),
        .s_axil_rresp      (periph_rresp),
        .s_axil_rvalid     (periph_rvalid),
        .s_axil_rready     (mem_axi_rready),
        .crc_m_axis_tdata  (crc_m_axis_tdata),
        .crc_m_axis_tvalid (crc_m_axis_tvalid),
        .crc_m_axis_tready (crc_m_axis_tready),
        .uart_rx           (uart_rx),
        .uart_tx           (uart_tx)
    );

endmodule
