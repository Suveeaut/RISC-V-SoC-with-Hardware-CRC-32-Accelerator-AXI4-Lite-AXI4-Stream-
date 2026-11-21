`timescale 1ns / 1ps

module tb_axis_crc32;

    localparam int CLK_PER = 10; // 100 MHz

    logic        clk;
    logic        rst;

    logic [7:0]  s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic [31:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tready;

    logic [31:0] golden_queue[$];
    int          pass_count = 0;
    int          fail_count = 0;

    axis_crc32 dut (
        .clk           (clk),
        .rst           (rst),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PER / 2) clk = ~clk;
    end

    // Golden reference CRC-32 function (IEEE 802.3 reflected)
    function automatic logic [31:0] calc_golden_crc32(input byte pkt[$]);
        logic [31:0] crc;
        crc = 32'hFFFF_FFFF;
        foreach (pkt[i]) begin
            crc = crc ^ {24'h0, pkt[i]};
            for (int b = 0; b < 8; b++) begin
                if (crc[0]) begin
                    crc = (crc >> 1) ^ 32'hEDB8_8320;
                end else begin
                    crc = (crc >> 1);
                end
            end
        end
        return crc ^ 32'hFFFF_FFFF;
    endfunction

    // Task to send a single packet with optional random valid/ready jitter
    task automatic send_packet(input byte pkt[$], input bit random_stall);
        byte temp_pkt[$];
        logic [31:0] exp_crc;

        foreach (pkt[i]) begin
            temp_pkt.push_back(pkt[i]);
        end
        exp_crc = calc_golden_crc32(temp_pkt);
        golden_queue.push_back(exp_crc);

        for (int idx = 0; idx < temp_pkt.size(); idx++) begin
            bit is_last;
            is_last = (idx == temp_pkt.size() - 1);

            @(posedge clk);
            if (random_stall) begin
                while ($urandom_range(0, 99) < 40) begin
                    s_axis_tvalid <= 1'b0;
                    s_axis_tlast  <= 1'b0;
                    @(posedge clk);
                end
            end

            s_axis_tdata  <= temp_pkt[idx];
            s_axis_tlast  <= is_last;
            s_axis_tvalid <= 1'b1;

            @(posedge clk);
            while (!(s_axis_tvalid && s_axis_tready)) begin
                @(posedge clk);
            end

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= 8'h00;
        end
    endtask

    // Random downstream backpressure on result stream
    always @(posedge clk) begin
        if (rst) begin
            m_axis_tready <= 1'b0;
        end else begin
            m_axis_tready <= ($urandom_range(0, 99) < 55);
        end
    end

    // Self-checking monitor against golden reference queue
    always @(posedge clk) begin
        if (!rst && m_axis_tvalid && m_axis_tready) begin
            if (golden_queue.size() == 0) begin
                $display("[FAIL] Unexpected CRC output 32'h%08h at t=%0t", m_axis_tdata, $time);
                fail_count++;
            end else begin
                logic [31:0] exp_c;
                exp_c = golden_queue.pop_front();
                if (m_axis_tdata === exp_c) begin
                    $display("[PASS] CRC-32 matched 32'h%08h at t=%0t", m_axis_tdata, $time);
                    pass_count++;
                end else begin
                    $display("[FAIL] CRC mismatch at t=%0t: expected 32'h%08h, got 32'h%08h",
                             $time, exp_c, m_axis_tdata);
                    fail_count++;
                end
            end
        end
    end

    initial begin
        byte std_vec[$];
        rst           <= 1'b1;
        s_axis_tdata  <= 8'h00;
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;

        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        // 1. Standard test vector "123456789" -> expected 32'hCBF4_3926
        std_vec = '{"1", "2", "3", "4", "5", "6", "7", "8", "9"};
        send_packet(std_vec, 1'b0);

        // 2. Randomized packets of varying lengths with stalls and backpressure
        for (int p = 0; p < 15; p++) begin
            byte rand_pkt[$];
            int pkt_len;
            pkt_len = $urandom_range(1, 24);
            for (int k = 0; k < pkt_len; k++) begin
                rand_pkt.push_back(byte'($urandom_range(0, 255)));
            end
            send_packet(rand_pkt, 1'b1);
        end

        // Wait until all expected CRC results are drained
        begin
            int wait_cycles = 0;
            while ((golden_queue.size() > 0 || m_axis_tvalid) && wait_cycles < 5000) begin
                @(posedge clk);
                wait_cycles++;
            end
            if (golden_queue.size() > 0) begin
                $display("[FAIL] Timeout with %0d CRC result(s) still pending", golden_queue.size());
                fail_count += golden_queue.size();
            end
        end

        repeat (20) @(posedge clk);

        $display("--------------------------------------------------");
        $display("AXI4-Stream CRC-32 Test: PASS=%0d, FAIL=%0d", pass_count, fail_count);
        $display("--------------------------------------------------");

        if (fail_count == 0 && pass_count > 0) begin
            $display("ALL CRC-32 TESTS PASSED!");
        end else begin
            $display("SOME CRC-32 TESTS FAILED!");
        end

        $finish;
    end

endmodule
