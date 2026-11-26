`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================================
// 1. Interface (matched to your axis_fifo ports)
// ============================================================================
interface axis_fifo_if #(parameter int DATA_WIDTH = 8) (
    input logic clk,
    input logic rst
);
    logic [DATA_WIDTH-1:0] s_axis_data;
    logic                  s_axis_valid;
    logic                  s_axis_ready;

    logic [DATA_WIDTH-1:0] m_axis_data;
    logic                  m_axis_valid;
    logic                  m_axis_ready;

    logic                  full;
    logic                  empty;
    logic                  almost_full;
    logic                  almost_empty;
endinterface

// ============================================================================
// 2. Sequence Item
// ============================================================================
class axis_item extends uvm_sequence_item;
    rand bit [7:0] data;
    rand int       pre_delay;

    constraint c_delay { pre_delay inside {[0:3]}; }

    `uvm_object_utils_begin(axis_item)
        `uvm_field_int(data,      UVM_ALL_ON)
        `uvm_field_int(pre_delay, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axis_item");
        super.new(name);
    endfunction
endclass

// ============================================================================
// 3. Sequence
// ============================================================================
class axis_rand_seq extends uvm_sequence #(axis_item);
    `uvm_object_utils(axis_rand_seq)

    int num_items = 30;

    function new(string name = "axis_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        axis_item item;
        repeat (num_items) begin
            item = axis_item::type_id::create("item");
            start_item(item);
            assert(item.randomize());
            finish_item(item);
        end
    endtask
endclass

// ============================================================================
// 4. Driver (Slave write side)
// ============================================================================
class axis_driver extends uvm_driver #(axis_item);
    `uvm_component_utils(axis_driver)

    virtual axis_fifo_if #(.DATA_WIDTH(8)) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axis_fifo_if #(.DATA_WIDTH(8)))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not found for axis_driver")
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_item item;
        vif.s_axis_valid <= 1'b0;
        vif.s_axis_data  <= '0;

        wait (vif.rst === 1'b0);
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(item);

            repeat (item.pre_delay) @(posedge vif.clk);

            vif.s_axis_valid <= 1'b1;
            vif.s_axis_data  <= item.data;

            @(posedge vif.clk);
            while (!vif.s_axis_ready) begin
                @(posedge vif.clk);
            end

            vif.s_axis_valid <= 1'b0;
            vif.s_axis_data  <= '0;

            seq_item_port.item_done();
        end
    endtask
endclass

// ============================================================================
// 5. Monitor (Observes slave write handshake & master read handshake)
// ============================================================================
class axis_monitor extends uvm_monitor;
    `uvm_component_utils(axis_monitor)

    virtual axis_fifo_if #(.DATA_WIDTH(8)) vif;
    uvm_analysis_port #(axis_item) tx_ap;
    uvm_analysis_port #(axis_item) rx_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        tx_ap = new("tx_ap", this);
        rx_ap = new("rx_ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axis_fifo_if #(.DATA_WIDTH(8)))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not found for axis_monitor")
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_item tx_item, rx_item;
        forever begin
            @(posedge vif.clk);
            if (vif.rst) continue;

            if (vif.s_axis_valid && vif.s_axis_ready) begin
                tx_item = axis_item::type_id::create("tx_item");
                tx_item.data = vif.s_axis_data;
                tx_ap.write(tx_item);
            end

            if (vif.m_axis_valid && vif.m_axis_ready) begin
                rx_item = axis_item::type_id::create("rx_item");
                rx_item.data = vif.m_axis_data;
                rx_ap.write(rx_item);
            end
        end
    endtask
endclass

// ============================================================================
// 6. Scoreboard
// ============================================================================
`uvm_analysis_imp_decl(_tx)
`uvm_analysis_imp_decl(_rx)

class axis_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axis_scoreboard)

    uvm_analysis_imp_tx #(axis_item, axis_scoreboard) tx_imp;
    uvm_analysis_imp_rx #(axis_item, axis_scoreboard) rx_imp;

    bit [7:0] exp_q[$];
    int       match_cnt = 0;
    int       err_cnt   = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        tx_imp = new("tx_imp", this);
        rx_imp = new("rx_imp", this);
    endfunction

    virtual function void write_tx(axis_item item);
        exp_q.push_back(item.data);
    endfunction

    virtual function void write_rx(axis_item item);
        bit [7:0] exp_data;
        if (exp_q.size() == 0) begin
            `uvm_error("SB_EMPTY", $sformatf("Received unexpected data 0x%0h when queue is empty", item.data))
            err_cnt++;
        end else begin
            exp_data = exp_q.pop_front();
            if (item.data !== exp_data) begin
                `uvm_error("SB_MISMATCH", $sformatf("Expected 0x%0h, got 0x%0h", exp_data, item.data))
                err_cnt++;
            end else begin
                match_cnt++;
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SB_SUMMARY", $sformatf("Matched=%0d, Errors=%0d, Remaining_in_Q=%0d",
                                          match_cnt, err_cnt, exp_q.size()), UVM_LOW)
    endfunction
endclass

// ============================================================================
// 7. Environment & Test
// ============================================================================
class axis_env extends uvm_env;
    `uvm_component_utils(axis_env)

    uvm_sequencer #(axis_item) seqr;
    axis_driver                drv;
    axis_monitor               mon;
    axis_scoreboard            sb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        seqr = uvm_sequencer#(axis_item)::type_id::create("seqr", this);
        drv  = axis_driver::type_id::create("drv", this);
        mon  = axis_monitor::type_id::create("mon", this);
        sb   = axis_scoreboard::type_id::create("sb", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
        mon.tx_ap.connect(sb.tx_imp);
        mon.rx_ap.connect(sb.rx_imp);
    endfunction
endclass

class axis_fifo_test extends uvm_test;
    `uvm_component_utils(axis_fifo_test)

    axis_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axis_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        axis_rand_seq seq;
        phase.raise_objection(this);

        seq = axis_rand_seq::type_id::create("seq");
        seq.num_items = 40;
        seq.start(env.seqr);

        #200ns;
        phase.drop_objection(this);
    endtask
endclass

// ============================================================================
// 8. Top Module & DUT Instantiation
// ============================================================================
module tb_uvm_axis_fifo;
    localparam int DATA_WIDTH = 8;
    localparam int DEPTH      = 16;

    logic clk = 1'b0;
    logic rst;

    always #5ns clk = ~clk; // 100 MHz

    axis_fifo_if #(.DATA_WIDTH(DATA_WIDTH)) vif (.clk(clk), .rst(rst));

    // Random backpressure on master side
    always @(posedge clk) begin
        if (rst)
            vif.m_axis_ready <= 1'b0;
        else
            vif.m_axis_ready <= ($urandom_range(0, 99) < 70);
    end

    axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH     (DEPTH)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .s_axis_data  (vif.s_axis_data),
        .s_axis_valid (vif.s_axis_valid),
        .s_axis_ready (vif.s_axis_ready),
        .m_axis_data  (vif.m_axis_data),
        .m_axis_valid (vif.m_axis_valid),
        .m_axis_ready (vif.m_axis_ready),
        .full         (vif.full),
        .empty        (vif.empty),
        .almost_full  (vif.almost_full),
        .almost_empty (vif.almost_empty)
    );

    initial begin
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
    end

    initial begin
        uvm_config_db#(virtual axis_fifo_if #(.DATA_WIDTH(DATA_WIDTH)))::set(null, "*", "vif", vif);
        run_test("axis_fifo_test");
    end
endmodule
