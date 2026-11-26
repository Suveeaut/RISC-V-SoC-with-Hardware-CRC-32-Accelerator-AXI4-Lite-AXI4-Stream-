`timescale 1ns / 1ps

module uart_tx_tb;

    logic       clk;
    logic       rst;
    logic       s_axis_valid;
    logic [7:0] s_axis_data;
    logic       tx;
    logic       s_axis_ready;

    uart_tx #(
        .CLK_FREQ  (1000000), 
        .BAUD_RATE (9600)    
    ) uut (
        .clk          (clk),
        .rst          (rst),
        .s_axis_valid (s_axis_valid),
        .s_axis_data  (s_axis_data),
        .tx           (tx),
        .s_axis_ready (s_axis_ready)
    );

    always #500 clk = ~clk;

    initial begin

        clk          = 0;
        rst          = 1;
        s_axis_valid = 0;
        s_axis_data  = 8'h00;

        #2000;
        rst = 0;
        #2000;

        wait (s_axis_ready); 
        @(posedge clk);
        s_axis_data  = 8'h41; 
        s_axis_valid = 1;    
        @(posedge clk);
        s_axis_valid = 0;    

        @(posedge s_axis_ready);
        #5000;

        wait (s_axis_ready);
        @(posedge clk);
        s_axis_data  = 8'h4B;
        s_axis_valid = 1;
        @(posedge clk);
        s_axis_valid = 0;

        @(posedge s_axis_ready);
        #10000;
        $finish;
    end

endmodule