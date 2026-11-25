`timescale 1ns / 1ps

module tb_axi4_lite_periph;

    localparam int CLK_PER = 10;

    localparam logic [7:0] ADDR_CRC_DATA_IN = 8'h00;
    localparam logic [7:0] ADDR_CRC_CTRL    = 8'h04;
    localparam logic [7:0] ADDR_CRC_RESULT  = 8'h08;
    localparam logic [7:0] ADDR_CRC_STATUS  = 8'h0C;
    localparam logic [7:0] ADDR_UART_TX     = 8'h10;
    localparam logic [7:0] ADDR_UART_RX     = 8'h14;
    localparam logic [7:0] ADDR_UART_STATUS = 8'h18;

    logic        clk;
    logic        rst;

    logic [7:0]  s_axil_awaddr;
    logic        s_axil_awvalid;
    logic        s_axil_awready;

    logic [31:0] s_axil_wdata;
    logic [3:0]  s_axil_wstrb;
    logic        s_axil_wvalid;
    logic        s_axil_wready;

    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid;
    logic        s_axil_bready;

    logic [7:0]  s_axil_araddr;
    logic        s_axil_arvalid;
    logic        s_axil_arready;

    logic [31:0] s_axil_rdata;
    logic [1:0]  s_axil_rresp;
    logic        s_axil_rvalid;
    logic        s_axil_rready;

    logic [31:0] crc_m_axis_tdata;
    logic        crc_m_axis_tvalid;
    logic        crc_m_axis_tready;

    logic        uart_rx;
    logic        uart_tx;

    int          pass_count = 0;
    int          fail_count = 0;

    axi4_lite_periph_top #(
        .ADDR_WIDTH    (8),
        .IN_FIFO_DEPTH (32),
        .OUT_FIFO_DEPTH(16)
    ) dut (
        .clk               (clk),
        .rst               (rst),
        .s_axil_awaddr     (s_axil_awaddr),
        .s_axil_awvalid    (s_axil_awvalid),
        .s_axil_awready    (s_axil_awready),
        .s_axil_wdata      (s_axil_wdata),
        .s_axil_wstrb      (s_axil_wstrb),
        .s_axil_wvalid     (s_axil_wvalid),
        .s_axil_wready     (s_axil_wready),
        .s_axil_bresp      (s_axil_bresp),
        .s_axil_bvalid     (s_axil_bvalid),
        .s_axil_bready     (s_axil_bready),
        .s_axil_araddr     (s_axil_araddr),
        .s_axil_arvalid    (s_axil_arvalid),
        .s_axil_arready    (s_axil_arready),
        .s_axil_rdata      (s_axil_rdata),
        .s_axil_rresp      (s_axil_rresp),
        .s_axil_rvalid     (s_axil_rvalid),
        .s_axil_rready     (s_axil_rready),
        .crc_m_axis_tdata  (crc_m_axis_tdata),
        .crc_m_axis_tvalid (crc_m_axis_tvalid),
        .crc_m_axis_tready (crc_m_axis_tready),
        .uart_rx           (uart_rx),
        .uart_tx           (uart_tx)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PER / 2) clk = ~clk;
    end

    task automatic axil_write(input logic [7:0] addr, input logic [31:0] data);
        int timeout;
        @(posedge clk);
        s_axil_awaddr  <= addr;
        s_axil_awvalid <= 1'b1;
        s_axil_wdata   <= data;
        s_axil_wstrb   <= 4'hF;
        s_axil_wvalid  <= 1'b1;
        s_axil_bready  <= 1'b1;

        timeout = 0;
        while (!(s_axil_awready && s_axil_wready) && timeout < 500) begin
            @(posedge clk);
            timeout++;
        end

        @(posedge clk);
        s_axil_awvalid <= 1'b0;
        s_axil_wvalid  <= 1'b0;

        timeout = 0;
        while (!s_axil_bvalid && timeout < 500) begin
            @(posedge clk);
            timeout++;
        end

        @(posedge clk);
        s_axil_bready  <= 1'b0;
    endtask

    task automatic axil_read(input logic [7:0] addr, output logic [31:0] rdata_out);
        int timeout;
        @(posedge clk);
        s_axil_araddr  <= addr;
        s_axil_arvalid <= 1'b1;
        s_axil_rready  <= 1'b1;

        timeout = 0;
        while (!s_axil_arready && timeout < 500) begin
            @(posedge clk);
            timeout++;
        end

        @(posedge clk);
        s_axil_arvalid <= 1'b0;

        timeout = 0;
        while (!s_axil_rvalid && timeout < 500) begin
            @(posedge clk);
            timeout++;
        end

        rdata_out = s_axil_rdata;
        @(posedge clk);
        s_axil_rready <= 1'b0;
    endtask

    function automatic logic [31:0] calc_golden_crc32(input byte pkt[$]);
        logic [31:0] crc;
        int i, b;
        crc = 32'hFFFF_FFFF;
        for (i = 0; i < pkt.size(); i++) begin
            crc = crc ^ {24'h0, pkt[i]};
            for (b = 0; b < 8; b++) begin
                if (crc[0]) crc = (crc >> 1) ^ 32'hEDB8_8320;
                else        crc = (crc >> 1);
            end
        end
        return crc ^ 32'hFFFF_FFFF;
    endfunction

    task automatic run_crc_packet_test(input byte pkt[$], input string tag);
        logic [31:0] exp_crc;
        logic [31:0] status_val;
        logic [31:0] got_crc;
        int i, wait_cnt;
        bit is_last;

        exp_crc = calc_golden_crc32(pkt);

        for (i = 0; i < pkt.size(); i++) begin
            is_last = (i == pkt.size() - 1);
            if (is_last) begin
                axil_write(ADDR_CRC_CTRL, 32'h0000_0001); // arm LAST_PULSE
            end
            axil_write(ADDR_CRC_DATA_IN, {24'h0, pkt[i]});
        end

        // Poll CRC_STATUS[0] (OUT_VALID)
        status_val = 32'h0;
        wait_cnt   = 0;
        while ((status_val[0] == 1'b0) && wait_cnt < 5000) begin
            axil_read(ADDR_CRC_STATUS, status_val);
            wait_cnt++;
        end

        if (status_val[0] == 1'b0) begin
            $display("[FAIL] %s: Timeout waiting for OUT_VALID", tag);
            fail_count++;
            return;
        end

        axil_read(ADDR_CRC_RESULT, got_crc);
        if (got_crc === exp_crc) begin
            $display("[PASS] %s: got CRC-32 = 32'h%08h", tag, got_crc);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected 32'h%08h, got 32'h%08h", tag, exp_crc, got_crc);
            fail_count++;
        end
    endtask

    initial begin
        byte vec_123456789[$];
        byte pkt_rand[$];
        logic [31:0] rd_val;
        int p, k, len;

        rst            <= 1'b1;
        s_axil_awaddr  <= 8'h00;
        s_axil_awvalid <= 1'b0;
        s_axil_wdata   <= 32'h0;
        s_axil_wstrb   <= 4'h0;
        s_axil_wvalid  <= 1'b0;
        s_axil_bready  <= 1'b0;
        s_axil_araddr  <= 8'h00;
        s_axil_arvalid <= 1'b0;
        s_axil_rready  <= 1'b0;
        crc_m_axis_tready <= 1'b0; // let CPU pop via AXI4-Lite CRC_RESULT
        uart_rx        <= 1'b1;

        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        // 1. Check initial CRC_STATUS
        axil_read(ADDR_CRC_STATUS, rd_val);
        if (rd_val[1] === 1'b1 && rd_val[2] === 1'b1) begin
            $display("[PASS] Initial CRC_STATUS shows IN_READY=1, IN_EMPTY=1 (val=32'h%08h)", rd_val);
            pass_count++;
        end else begin
            $display("[FAIL] Unexpected initial CRC_STATUS = 32'h%08h", rd_val);
            fail_count++;
        end

        // 2. Standard vector "123456789" -> 32'hCBF4_3926
        vec_123456789 = '{"1", "2", "3", "4", "5", "6", "7", "8", "9"};
        run_crc_packet_test(vec_123456789, "VEC_123456789");

        // 3. Random packets
        for (p = 0; p < 10; p++) begin
            pkt_rand.delete();
            len = $urandom_range(1, 12);
            for (k = 0; k < len; k++) begin
                pkt_rand.push_back(byte'($urandom_range(0, 255)));
            end
            run_crc_packet_test(pkt_rand, $sformatf("RAND_PKT_%0d", p));
        end

        $display("-------------------------------------------------------");
        $display("AXI4-Lite Peripheral Test: PASS=%0d, FAIL=%0d", pass_count, fail_count);
        $display("-------------------------------------------------------");

        if (fail_count == 0 && pass_count > 0) begin
            $display("ALL AXI4-LITE PERIPHERAL TESTS PASSED!");
        end else begin
            $display("SOME AXI4-LITE PERIPHERAL TESTS FAILED!");
        end

        $finish;
    end

endmodule
