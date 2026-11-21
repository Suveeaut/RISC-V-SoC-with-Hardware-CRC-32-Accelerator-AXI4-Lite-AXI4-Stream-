`timescale 1ns / 1ps

module tb_crc32_sw_vs_hw_bench;

    localparam int CLK_PER = 10; // 100 MHz (10 ns)

    // RV32I instruction encoders
    function automatic logic [31:0] enc_lui(input int rd, input logic [31:0] imm_u);
        logic [4:0] rd_v;
        rd_v = rd[4:0];
        return {imm_u[31:12], rd_v, 7'b0110111};
    endfunction

    function automatic logic [31:0] enc_addi(input int rd, input int rs1, input int imm_i);
        logic [4:0]  rd_v, rs1_v;
        logic [11:0] imm_v;
        rd_v  = rd[4:0];
        rs1_v = rs1[4:0];
        imm_v = imm_i[11:0];
        return {imm_v, rs1_v, 3'b000, rd_v, 7'b0010011};
    endfunction

    function automatic logic [31:0] enc_andi(input int rd, input int rs1, input int imm_i);
        logic [4:0]  rd_v, rs1_v;
        logic [11:0] imm_v;
        rd_v  = rd[4:0];
        rs1_v = rs1[4:0];
        imm_v = imm_i[11:0];
        return {imm_v, rs1_v, 3'b111, rd_v, 7'b0010011};
    endfunction

    function automatic logic [31:0] enc_srli(input int rd, input int rs1, input int shamt);
        logic [4:0] rd_v, rs1_v;
        logic [4:0] sh_v;
        rd_v  = rd[4:0];
        rs1_v = rs1[4:0];
        sh_v  = shamt[4:0];
        return {7'b0000000, sh_v, rs1_v, 3'b101, rd_v, 7'b0010011};
    endfunction

    function automatic logic [31:0] enc_xori(input int rd, input int rs1, input int imm_i);
        logic [4:0]  rd_v, rs1_v;
        logic [11:0] imm_v;
        rd_v  = rd[4:0];
        rs1_v = rs1[4:0];
        imm_v = imm_i[11:0];
        return {imm_v, rs1_v, 3'b100, rd_v, 7'b0010011};
    endfunction

    function automatic logic [31:0] enc_xor(input int rd, input int rs1, input int rs2);
        logic [4:0] rd_v, rs1_v, rs2_v;
        rd_v  = rd[4:0];
        rs1_v = rs1[4:0];
        rs2_v = rs2[4:0];
        return {7'b0000000, rs2_v, rs1_v, 3'b100, rd_v, 7'b0110011};
    endfunction

    function automatic logic [31:0] enc_lw(input int rd, input int rs1, input int imm_i);
        logic [4:0]  rd_v, rs1_v;
        logic [11:0] imm_v;
        rd_v  = rd[4:0];
        rs1_v = rs1[4:0];
        imm_v = imm_i[11:0];
        return {imm_v, rs1_v, 3'b010, rd_v, 7'b0000011};
    endfunction

    function automatic logic [31:0] enc_sw(input int rs2, input int rs1, input int imm_s);
        logic [4:0]  rs2_v, rs1_v;
        logic [11:0] imm_v;
        rs2_v = rs2[4:0];
        rs1_v = rs1[4:0];
        imm_v = imm_s[11:0];
        return {imm_v[11:5], rs2_v, rs1_v, 3'b010, imm_v[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] enc_beq(input int rs1, input int rs2, input int imm_b);
        logic [4:0]  rs1_v, rs2_v;
        logic [12:0] imm_v;
        rs1_v = rs1[4:0];
        rs2_v = rs2[4:0];
        imm_v = imm_b[12:0];
        return {imm_v[12], imm_v[10:5], rs2_v, rs1_v, 3'b000, imm_v[4:1], imm_v[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] enc_bne(input int rs1, input int rs2, input int imm_b);
        logic [4:0]  rs1_v, rs2_v;
        logic [12:0] imm_v;
        rs1_v = rs1[4:0];
        rs2_v = rs2[4:0];
        imm_v = imm_b[12:0];
        return {imm_v[12], imm_v[10:5], rs2_v, rs1_v, 3'b001, imm_v[4:1], imm_v[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] enc_jal(input int rd, input int imm_j);
        logic [4:0]  rd_v;
        logic [20:0] imm_v;
        rd_v  = rd[4:0];
        imm_v = imm_j[20:0];
        return {imm_v[20], imm_v[10:1], imm_v[11], imm_v[19:12], rd_v, 7'b1101111};
    endfunction

    logic        clk;
    logic        rst_n;
    logic [31:0] crc_m_axis_tdata;
    logic        crc_m_axis_tvalid;
    logic        crc_m_axis_tready;
    logic        uart_rx;
    logic        uart_tx;

    localparam logic [31:0] SENTINEL_VAL = 32'hDEAD_BEEF;

    picorv32_periph_soc #(
        .MEM_WORDS(1024)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
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

    // 1) Software CRC-32 (4 bytes "1234") -> store result at SRAM[0x0100] (word 64)
    task automatic load_sw_crc32_prog;
        int w;
        w = 0;

        dut.ram[w] = enc_lui(10, 32'h3433_3000);       w++;
        dut.ram[w] = enc_addi(10, 10, 12'h231);        w++;
        dut.ram[w] = enc_addi(11, 0, 4);               w++;
        dut.ram[w] = enc_lui(12, 32'hFFFF_F000);       w++;
        dut.ram[w] = enc_addi(12, 12, -1);             w++;
        dut.ram[w] = enc_lui(13, 32'hEDB8_8000);       w++;
        dut.ram[w] = enc_addi(13, 13, 12'h320);        w++;
        dut.ram[w] = enc_addi(14, 0, 256);             w++; // 0x0100 (word 64)

        // Byte loop (w = 8)
        dut.ram[w] = enc_andi(15, 10, 12'h0FF);        w++;
        dut.ram[w] = enc_srli(10, 10, 5'd8);           w++;
        dut.ram[w] = enc_xor(12, 12, 15);              w++;
        dut.ram[w] = enc_addi(16, 0, 8);               w++;

        // Bit loop (w = 12)
        dut.ram[w] = enc_andi(17, 12, 12'h001);        w++;
        dut.ram[w] = enc_srli(12, 12, 5'd1);           w++;
        dut.ram[w] = enc_beq(17, 0, 8);                w++;
        dut.ram[w] = enc_xor(12, 12, 13);              w++;

        dut.ram[w] = enc_addi(16, 16, -1);             w++;
        dut.ram[w] = enc_bne(16, 0, -20);              w++;

        dut.ram[w] = enc_addi(11, 11, -1);             w++;
        dut.ram[w] = enc_bne(11, 0, -44);              w++;

        dut.ram[w] = enc_xori(12, 12, -1);             w++;
        dut.ram[w] = enc_sw(12, 14, 12'h000);          w++;
        dut.ram[w] = enc_jal(0, 0);                    w++;
    endtask

    // 2) Hardware CRC-32 (4 bytes "1234") -> store result at SRAM[0x0104] (word 65)
    task automatic load_hw_crc32_prog;
        int w;
        w = 0;

        dut.ram[w] = enc_lui(10, 32'h4000_0000);       w++;
        dut.ram[w] = enc_addi(11, 0, 260);             w++; // 0x0104 (word 65)
        dut.ram[w] = enc_addi(13, 0, 1);               w++; // LAST_PULSE = 1

        // Send '1', '2', '3'
        dut.ram[w] = enc_addi(12, 0, 8'h31);           w++;
        dut.ram[w] = enc_sw(12, 10, 12'h000);          w++;
        dut.ram[w] = enc_addi(12, 0, 8'h32);           w++;
        dut.ram[w] = enc_sw(12, 10, 12'h000);          w++;
        dut.ram[w] = enc_addi(12, 0, 8'h33);           w++;
        dut.ram[w] = enc_sw(12, 10, 12'h000);          w++;

        // Set LAST_PULSE and send '4'
        dut.ram[w] = enc_sw(13, 10, 12'h004);          w++;
        dut.ram[w] = enc_addi(12, 0, 8'h34);           w++;
        dut.ram[w] = enc_sw(12, 10, 12'h000);          w++;

        // Read CRC_RESULT (0x008) and write to SRAM[0x0104] (word 65)
        dut.ram[w] = enc_lw(14, 10, 12'h008);          w++;
        dut.ram[w] = enc_sw(14, 11, 12'h000);          w++;
        dut.ram[w] = enc_jal(0, 0);                    w++;
    endtask

    task automatic prep_reset_and_ram;
        int i;
        rst_n             = 1'b0;
        uart_rx           = 1'b1;
        crc_m_axis_tready = 1'b0;
        for (i = 0; i < 1024; i++) begin
            dut.ram[i] = SENTINEL_VAL;
        end
        repeat (8) @(posedge clk);
    endtask

    task automatic run_and_measure_word(
        input  string       mode_name,
        input  int          target_word,
        output int          cycles_taken,
        output logic [31:0] got_crc
    );
        int c;
        cycles_taken = 0;
        c = 0;
        @(negedge clk);
        rst_n = 1'b1;

        while (c < 50000) begin
            @(posedge clk);
            c++;
            if (dut.ram[target_word] !== SENTINEL_VAL) begin
                cycles_taken = c;
                break;
            end
        end
        got_crc = dut.ram[target_word];
        $display("[%s] Cycles=%0d | Latency (at 100MHz)=%0d ns | Result=32'h%08h",
                 mode_name, cycles_taken, cycles_taken * CLK_PER, got_crc);
    endtask

    int          sw_cycles, hw_cycles;
    logic [31:0] sw_crc, hw_crc;
    real         speedup;

    initial begin
        // Run SW benchmark (result -> word 64)
        prep_reset_and_ram();
        load_sw_crc32_prog();
        run_and_measure_word("SW_CRC32", 64, sw_cycles, sw_crc);

        // Run HW benchmark (result -> word 65)
        prep_reset_and_ram();
        load_hw_crc32_prog();
        run_and_measure_word("HW_CRC32", 65, hw_cycles, hw_crc);

        if (hw_cycles > 0) begin
            speedup = real'(sw_cycles) / real'(hw_cycles);
            $display("-------------------------------------------------------------------------");
            $display("Benchmark Summary (4 bytes \"1234\"): SW=%0d cycles vs HW=%0d cycles | Speedup=%.2fx",
                     sw_cycles, hw_cycles, speedup);
            $display("-------------------------------------------------------------------------");
        end

        $finish;
    end

endmodule
