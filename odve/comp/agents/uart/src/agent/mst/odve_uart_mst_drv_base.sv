// Master (DTE) driver: transmits the sequence's items on txd at
// cfg.tx_bit() clocks per bit, after item.idle_bits bit times of mark.
//   DATA    one character in cfg's format (+ injected parity / stop errors);
//           with cfg.flow_ctrl it first waits for cts_n low (auto-CTS:
//           checked before each start bit, a character once started is sent
//           whole)
//   BREAK   space for brk_bits bit times, then one bit of mark
//   GLITCH  space for glitch_clks clocks (a false start bit), then one bit of mark
// The receive side of the master is its monitor; rts_n ("I can receive")
// is driven low after reset and changed by set_rx_ready() from the test.
class odve_uart_mst_drv_base extends uvm_driver #(odve_uart_item);
    `uvm_component_utils(odve_uart_mst_drv_base)

    virtual odve_uart_if vif;
    odve_uart_cfg        cfg;
    int unsigned         n_sent      = 0;
    int unsigned         n_cts_stall = 0;   // characters that had to wait for cts_n

    function new(string name = "odve_uart_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // rts_n low = ready to receive (the peer's auto-CTS)
    function void set_rx_ready(bit rdy);
        vif.rts_n <= !rdy;
    endfunction

    // Line levels before anything runs, so a test's set_rx_ready() at the
    // start of run_phase is not overwritten.
    virtual function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        vif.txd   <= 1'b1;
        vif.rts_n <= 1'b0;
    endfunction

    virtual task run_phase(uvm_phase phase);
        wait (vif.rst_n === 1'b1);
        repeat (cfg.tx_bit()) @(posedge vif.clk);    // one bit of mark after reset: receivers see the line idle first
        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_item(odve_uart_item it);
        int unsigned bc = cfg.tx_bit();
        repeat (it.idle_bits * bc) @(posedge vif.clk);
        case (it.kind)
            ODVE_UART_DATA: begin
                if (cfg.flow_ctrl && vif.cts_n !== 1'b0) begin
                    n_cts_stall++;
                    while (vif.cts_n !== 1'b0) @(posedge vif.clk);
                end
                odve_uart_phy::send(vif, 0, cfg, it, bc);
                n_sent++;
            end
            ODVE_UART_BREAK: begin
                vif.txd <= 1'b0;
                repeat (it.brk_bits * bc) @(posedge vif.clk);
                vif.txd <= 1'b1;
                repeat (bc) @(posedge vif.clk);
            end
            ODVE_UART_GLITCH: begin
                vif.txd <= 1'b0;
                repeat (it.glitch_clks) @(posedge vif.clk);
                vif.txd <= 1'b1;
                repeat (bc) @(posedge vif.clk);
            end
            default: ;
        endcase
        `uvm_info(get_name(), $sformatf("sent %s", it.convert2string()), UVM_HIGH)
    endtask
endclass
