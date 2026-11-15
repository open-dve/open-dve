// RTS/CTS hardware flow control on both sides. The master is not ready
// (rts_n high) while it sends 24 characters back to back: the peer must
// not send (auto-CTS), its FIFO fills, it raises its RTS (the master's
// cts_n) and the master must stall (auto-CTS) - no overrun. Once the master
// is ready, all 24 come back.
class flow_test extends base_test;
    `uvm_component_utils(flow_test)

    function new(string name = "flow_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        set_format(8, ODVE_UART_PAR_NONE, ODVE_UART_STOP1, 1);
        env_o.agt.drv.set_rx_ready(0);
        fork
            send(24, 0);
            begin
                repeat (20 * 10 * env_o.cfg.bit_clks) @(posedge env_o.cfg.vif.clk);
                if (env_o.scb_o.n_rx != 0)
                    `uvm_error(get_name(), $sformatf("peer sent %0d character(s) while the master was not ready", env_o.scb_o.n_rx))
                if (env_o.agt.drv.n_cts_stall == 0)
                    `uvm_error(get_name(), "the master was never held off by cts_n")
                env_o.agt.drv.set_rx_ready(1);
            end
        join
        wait_drain();
        // and with both sides ready the whole time
        set_format(7, ODVE_UART_PAR_EVEN, ODVE_UART_STOP1, 1);
        send(24, 0);
        wait_drain();
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.scb_o.n_echo != 48)
            `uvm_error(get_name(), $sformatf("%0d echoes, 48 expected", env_o.scb_o.n_echo))
        `uvm_info(get_name(), $sformatf("master held off by cts_n before %0d character(s)", env_o.agt.drv.n_cts_stall), UVM_LOW)
    endfunction
endclass : flow_test
