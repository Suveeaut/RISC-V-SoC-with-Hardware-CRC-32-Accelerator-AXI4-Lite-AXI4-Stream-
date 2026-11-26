`timescale 1ns / 1ps

module tb_uart_transceiver;

    // 10 MHz clock and 1 Mbps baud rate (10 clocks per bit) for fast simulation
    localparam int CLK_FREQ   = 10_000_000;
    localparam int BAUD_RATE  = 1_000_000;
    localparam int CLK_PER    = 100; // 100 ns -> 10 MHz
    localparam int FIFO_DEPTH = 8;

    logic clk;
    logic rst;

    logic       serial_line;
    logic [7:0] s_axis_tx_data;
    logic       s_axis_tx_valid;
    logic       s_axis_tx_ready;

    logic [7:0] m_axis_rx_data;
    logic       m_axis_rx_valid;
    logic       m_axis_rx_ready;

    logic tx_fifo_full, tx_fifo_empty, tx_fifo_almost_full, tx_fifo_almost_empty;
    logic rx_fifo_full, rx_fifo_empty, rx_fifo_almost_full, rx_fifo_almost_empty;

    byte exp_queue[$];
    int  pass_count = 0;
    int  fail_count = 0;

    uart_transceiver #(
        .CLK_FREQ     (CLK_FREQ),
        .BAUD_RATE    (BAUD_RATE),
        .FIFO_DEPTH   (FIFO_DEPTH),
        .AFULL_THRESH (FIFO_DEPTH - 2),
        .AEMPTY_THRESH(2)
    ) dut (
        .clk                 (clk),
        .rst                 (rst),
        .rx                  (serial_line),
        .tx                  (serial_line),
        .s_axis_tx_data      (s_axis_tx_data),
        .s_axis_tx_valid     (s_axis_tx_valid),
        .s_axis_tx_ready     (s_axis_tx_ready),
        .m_axis_rx_data      (m_axis_rx_data),
        .m_axis_rx_valid     (m_axis_rx_valid),
        .m_axis_rx_ready     (m_axis_rx_ready),
        .tx_fifo_full        (tx_fifo_full),
        .tx_fifo_empty       (tx_fifo_empty),
        .tx_fifo_almost_full (tx_fifo_almost_full),
        .tx_fifo_almost_empty(tx_fifo_almost_empty),
        .rx_fifo_full        (rx_fifo_full),
        .rx_fifo_empty       (rx_fifo_empty),
        .rx_fifo_almost_full (rx_fifo_almost_full),
        .rx_fifo_almost_empty(rx_fifo_almost_empty)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PER / 2) clk = ~clk;
    end

    // Task to push a single byte into TX FIFO via exact 1-beat AXI4-Stream handshake
    task automatic push_tx_byte(input byte b);
        @(posedge clk);
        while (!s_axis_tx_ready) begin
            @(posedge clk);
        end
        s_axis_tx_data  <= b;
        s_axis_valid    : begin
            s_axis_tx_valid <= 1'b1;
        end
        exp_queue.push_back(b);

        // Wait until the clock edge where both valid and ready are sampled high
        @(posedge clk);
        while (!(s_axis_tx_valid && s_axis_tx_ready)) begin
            @(posedge clk);
        end

        // Deassert valid immediately after the handshake edge so the beat is written once
        s_axis_tx_valid <= 1'b0;
        s_axis_tx_data  <= '0;
    endtask

    // Randomized downstream backpressure on RX FIFO master port
    always @(posedge clk) begin
        if (rst) begin
            m_axis_rx_ready <= 1'b0;
        end else begin
            // 50% ready, 50% backpressure to stress RX FIFO holding
            m_axis_rx_ready <= ($urandom_range(0, 99) < 50);
        end
    end

    // Scoreboard checker on RX FIFO AXI4-Stream output
    always @(posedge clk) begin
        if (!rst && m_axis_rx_valid && m_axis_rx_ready) begin
            if (exp_queue.size() == 0) begin
                $display("[FAIL] Unexpected byte 8'h%02h at t=%0t", m_axis_rx_data, $time);
                fail_count++;
            end else begin
                byte exp_b;
                exp_b = exp_queue.pop_front();
                if (m_axis_rx_data === exp_b) begin
                    $display("[PASS] Transceiver matched 8'h%02h at t=%0t", m_axis_rx_data, $time);
                    pass_count++;
                end else begin
                    $display("[FAIL] Mismatch at t=%0t: expected 8'h%02h, got 8'h%02h",
                             $time, exp_b, m_axis_rx_data);
                    fail_count++;
                end
            end
        end
    end

    initial begin
        rst             <= 1'b1;
        s_axis_tx_data  <= '0;
        s_axis_tx_valid <= 1'b0;

        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        // Send a burst of 8 bytes rapidly into TX FIFO
        for (int i = 0; i < 8; i++) begin
            push_tx_byte(byte'(8'h10 + i));
        end

        // Wait until all 8 bytes are serialized, received, and popped from RX FIFO
        begin
            int wait_cycles = 0;
            while ((exp_queue.size() > 0) && (wait_cycles < 20000)) begin
                @(posedge clk);
                wait_cycles++;
            end
            if (exp_queue.size() > 0) begin
                $display("[FAIL] Timeout waiting for %0d remaining byte(s)", exp_queue.size());
                fail_count += exp_queue.size();
            end
        end

        // Allow a few extra cycles for status flags to settle
        repeat (20) @(posedge clk);

        if (!tx_fifo_empty || !rx_fifo_empty) begin
            $display("[FAIL] FIFOs not empty at end: tx_empty=%b rx_empty=%b",
                     tx_fifo_empty, rx_fifo_empty);
            fail_count++;
        end

        $display("--------------------------------------------------");
        $display("UART Transceiver Test: PASS=%0d, FAIL=%0d", pass_count, fail_count);
        $display("--------------------------------------------------");

        if (fail_count == 0 && pass_count > 0) begin
            $display("ALL TRANSCEIVER TESTS PASSED!");
        end else begin
            $display("SOME TRANSCEIVER TESTS FAILED!");
        end

        $finish;
    end

endmodule
