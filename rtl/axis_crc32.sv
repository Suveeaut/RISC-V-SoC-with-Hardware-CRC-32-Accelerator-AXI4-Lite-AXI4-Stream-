`timescale 1ns / 1ps

module axis_crc32 #(
    parameter logic [31:0] POLY      = 32'hEDB8_8320, // Reflected IEEE 802.3 polynomial
    parameter logic [31:0] INIT_CRC  = 32'hFFFF_FFFF,
    parameter logic [31:0] FINAL_XOR = 32'hFFFF_FFFF
)(
    input  logic        clk,
    input  logic        rst,

    // AXI4-Stream Slave input (byte stream with packet boundary via s_axis_last)
    input  logic [7:0]  s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    // AXI4-Stream Master output (32-bit CRC-32 result per packet)
    output logic [31:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready
);

    typedef enum logic [1:0] {
        S_COLLECT = 2'd0, // Accept bytes and update running CRC state
        S_HOLD_OUT = 2'd1 // Hold computed CRC-32 until master accepts it
    } state_t;

    state_t      state;
    logic [31:0] crc_reg;

    // Combinational next-CRC calculation for a single incoming byte (LSB-first / reflected)
    function automatic logic [31:0] next_crc32_byte(
        input logic [31:0] curr_crc,
        input logic [7:0]  data_byte
    );
        logic [31:0] c;
        c = curr_crc ^ {24'h0, data_byte};
        for (int b = 0; b < 8; b++) begin
            if (c[0]) begin
                c = (c >> 1) ^ POLY;
            end else begin
                c = (c >> 1);
            end
        end
        return c;
    endfunction

    wire s_fire = s_axis_tvalid && s_axis_tready;
    wire m_fire = m_axis_tvalid && m_axis_tready;

    // Can accept input bytes only while collecting and no unaccepted result is pending
    assign s_axis_tready = (state == S_COLLECT) && (!m_axis_tvalid || m_fire);

    always_ff @(posedge clk) begin
        if (rst) begin
            state         <= S_COLLECT;
            crc_reg       <= INIT_CRC;
            m_axis_tdata  <= 32'h0;
            m_axis_tvalid <= 1'b0;
        end else begin
            // Clear output valid once accepted by downstream master
            if (m_fire) begin
                m_axis_tvalid <= 1'b0;
            end

            case (state)
                S_COLLECT: begin
                    if (s_fire) begin
                        logic [31:0] updated_crc;
                        updated_crc = next_crc32_byte(crc_reg, s_axis_tdata);

                        if (s_axis_tlast) begin
                            // End of packet: output finalized CRC-32 and reset running state
                            m_axis_tdata  <= updated_crc ^ FINAL_XOR;
                            m_axis_tvalid <= 1'b1;
                            crc_reg       <= INIT_CRC;

                            // If downstream isn't ready right away, hold output state
                            if (!m_axis_tready) begin
                                state <= S_HOLD_OUT;
                            end
                        end else begin
                            crc_reg <= updated_crc;
                        end
                    end
                end

                S_HOLD_OUT: begin
                    if (m_fire) begin
                        m_axis_tvalid <= 1'b0;
                        state         <= S_COLLECT;
                    end
                end

                default: begin
                    state         <= S_COLLECT;
                    crc_reg       <= INIT_CRC;
                    m_axis_tvalid <= 1'b0;
                end
            endcase
        end
    end

endmodule
