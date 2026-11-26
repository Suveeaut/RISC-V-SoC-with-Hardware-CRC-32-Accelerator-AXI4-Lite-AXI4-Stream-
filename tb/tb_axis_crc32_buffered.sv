`timescale 1ns / 1ps

module tb_axis_crc32_buffered;

    localparam int CLK_PER = 10;

    logic        clk;
    logic        rst;

    logic [7:0]  s_axis_in_tdata;
    logic        s_axis_in_tvalid;
    logic        s_axis_in_tready;
    logic        s_axis_in_tlast;

    logic [31:0] m_axis_out_tdata;
    logic        m_axis_out_tvalid;
    logic        m_axis_out_tready;

    logic        in_fifo_full, in_fifo_empty, in_fifo_almost_full, in_fifo_almost_empty;
    logic        out_fifo_full, out_fifo_empty, out_fifo_almost_full, out_fifo_almost_empty;

    logic [31:0] golden_queue[$];
    logic [31:0] exp_c;
    int          pass_count = 0;
    int          fail_count = 0;

    axis_crc32_buffered #(
        .IN_FIFO_DEPTH (32),
        .OUT_FIFO_DEPTH(16)
    ) dut (
        .clk                   (clk),
        .rst                   (rst),
        .s_axis_in_tdata       (s_axis_in_tdata),
        .s_axis_in_tvalid      (s_axis_in_tvalid),
        .s_axis_in_tready      (s_axis_in_tready),
        .s_axis_in_tlast       (s_axis_in_tlast),
        .m_axis_out_tdata      (m_axis_out_tdata),
        .m_axis_out_tvalid     (m_axis_out_tvalid),
        .m_axis_out_tready     (m_axis_out_tready),
        .in_fifo_full          (in_fifo_full),
        .in_fifo_empty         (in_fifo_empty),
        .in_fifo_almost_full   (in_fifo_almost_full),
        .in_fifo_almost_empty  (in_fifo_almost_empty),
        .out_fifo_full         (out_fifo_full),
        .out_fifo_empty        (out_fifo_empty),
        .out_fifo_almost_full  (out_fifo_almost_full),
        .out_fifo_almost_empty (out_fifo_almost_empty)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PER / 2) clk = ~clk;
    end

    function automatic logic [31:0] calc_golden_crc32(input byte pkt[$]);
        logic [31:0] crc;
        int i, b;
        crc = 32'hFFFF_FFFF;
        for (i = 0; i < pkt.size(); i++) begin
            crc = crc ^ {24'h0, pkt[i]};
            for (b = 0; b < 8; b++) begin
                if (crc[0]) begin
                    crc = (crc >> 1) ^ 32'hEDB8_8320;
                end else begin
                    crc = (crc >> 1);
                end
            end
        end
        return crc ^ 32'hFFFF_FFFF;
    endfunction

    task automatic send_packet_burst(input byte pkt[$]);
        byte temp_pkt[$];
        logic [31:0] exp_crc;
        int i, idx;
        bit is_last;

        for (i = 0; i < pkt.size(); i++) begin
            temp_pkt.push_back(pkt[i]);
        end
        exp_crc = calc_golden_crc32(temp_pkt);
        golden_queue.push_back(exp_crc);

        for (idx = 0; idx < temp_pkt.size(); idx++) begin
            is_last = (idx == temp_pkt.size() - 1);

            @(posedge clk);
            while (!s_axis_in_tready) begin
                @(posedge clk);
            end

            s_axis_in_tdata  <= temp_pkt[idx];
            s_axis_in_tlast  <= is_last;
            s_axis_in_tvalid <= 1'b1;

            @(posedge clk);
            while (!(s_axis_in_tvalid && s_axis_in_tready)) begin
                @(posedge clk);
            end

            s_axis_in_tvalid <= 1'b0;
            s_axis_in_tlast  <= 1'b0;
            s_axis_in_tdata  <= 8'h00;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            m_axis_out_tready <= 1'b0;
        end else begin
            m_axis_out_tready <= ($urandom_range(0, 99) < 35);
        end
    end

    always @(posedge clk) begin
        if (!rst && m_axis_out_tvalid && m_axis_out_tready) begin
            if (golden_queue.size() == 0) begin
                $display("[FAIL] Unexpected CRC output 32'h%08h at t=%0t", m_axis_out_tdata, $time);
                fail_count++;
            end else begin
                exp_c = golden_queue.pop_front();
                if (m_axis_out_tdata === exp_c) begin
                    $display("[PASS] Buffered CRC-32 matched 32'h%08h at t=%0t", m_axis_out_tdata, $time);
                    pass_count++;
                end else begin
                    $display("[FAIL] Mismatch at t=%0t: expected 32'h%08h, got 32'h%08h",
                             $time, exp_c, m_axis_out_tdata);
                    fail_count++;
                end
            end
        end
    end

    initial begin
        byte vec_123456789[$];
        byte rand_pkt[$];
        int p, k, pkt_len, wait_cycles;

        rst              <= 1'b1;
        s_axis_in_tdata  <= 8'h00;
        s_axis_in_tvalid <= 1'b0;
        s_axis_in_tlast  <= 1'b0;

        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        vec_123456789 = '{"1", "2", "3", "4", "5", "6", "7", "8", "9"};
        send_packet_burst(vec_123456789);

        for (p = 0; p < 20; p++) begin
            rand_pkt.delete();
            pkt_len = $urandom_range(1, 16);
            for (k = 0; k < pkt_len; k++) begin
                rand_pkt.push_back(byte'($urandom_range(0, 255)));
            end
            send_packet_burst(rand_pkt);
        end

        wait_cycles = 0;
        while ((golden_queue.size() > 0 || !in_fifo_empty || !out_fifo_empty) && wait_cycles < 10000) begin
            @(posedge clk);
            wait_cycles++;
        end
        if (golden_queue.size() > 0) begin
            $display("[FAIL] Timeout with %0d CRC result(s) remaining", golden_queue.size());
            fail_count += golden_queue.size();
        end

        repeat (20) @(posedge clk);

        if (!in_fifo_empty || !out_fifo_empty) begin
            $display("[FAIL] FIFOs not empty at end: in_empty=%b out_empty=%b",
                     in_fifo_empty, out_fifo_empty);
            fail_count++;
        end

        $display("-------------------------------------------------------");
        $display("Buffered AXI4-Stream CRC-32 Test: PASS=%0d, FAIL=%0d", pass_count, fail_count);
        $display("-------------------------------------------------------");

        if (fail_count == 0 && pass_count > 0) begin
            $display("ALL BUFFERED CRC-32 TESTS PASSED!");
        end else begin
            $display("SOME BUFFERED CRC-32 TESTS FAILED!");
        end

        $finish;
    end

endmodule
