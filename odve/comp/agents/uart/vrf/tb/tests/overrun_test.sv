// Receiver overrun (RTL device only, +uart_slave=dut): the device's auto
// flow control is on, so with the master not ready (rts_n high) it holds
// every character in its 8-entry FIFO; the master ignores the device's RTS
// and sends 11 back to back. The last 3 find the FIFO full: each must be
// reported as an overrun and lost, the first 8 echoed once the master is
// ready again.
class overrun_test extends base_test;
    `uvm_component_utils(overrun_test)

    localparam int unsigned DEPTH = 8, EXTRA = 3;

    function new(string name = "overrun_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    // after the env's build_phase has made cfg / scb_o
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        env_o.scb_o.expect_oe = 1;
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        if (env_o.cc_o.slave_is_agent())
            `uvm_fatal(get_name(), "overrun_test checks the RTL device's status pins: run it with +uart_slave=dut")
        set_format(8, ODVE_UART_PAR_ODD, ODVE_UART_STOP1, 1);
        env_o.cfg.flow_ctrl = 0;               // the master ignores the device's RTS
        env_o.agt.drv.set_rx_ready(0);
        send(DEPTH + EXTRA, 0);
        repeat (4 * 12 * env_o.cfg.bit_clks) @(posedge env_o.cfg.vif.clk);
        if (env_o.scb_o.n_rx != 0)
            `uvm_error(get_name(), $sformatf("device sent %0d character(s) while the master was not ready", env_o.scb_o.n_rx))
        env_o.agt.drv.set_rx_ready(1);
        wait_drain();
        send(8);                               // and it works normally afterwards
        wait_drain();
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.scb_o.n_oe != EXTRA)
            `uvm_error(get_name(), $sformatf("%0d overruns reported, %0d expected", env_o.scb_o.n_oe, EXTRA))
        if (env_o.scb_o.n_echo != DEPTH + 8)
            `uvm_error(get_name(), $sformatf("%0d echoes, %0d expected", env_o.scb_o.n_echo, DEPTH + 8))
    endfunction
endclass : overrun_test
