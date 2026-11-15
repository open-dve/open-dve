// Error injection on txd: bad parity, missing stop bit (framing error),
// break, glitch (false start bit), mixed with good characters, in three
// formats. The peer must not echo an errored character, must resynchronise
// on the next good one and (RTL) report each error on its status pins with
// the flags the monitor saw; a glitch must produce nothing at all.
class err_test extends base_test;
    `uvm_component_utils(err_test)

    function new(string name = "err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    // after the env's build_phase has made cfg / scb_o
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        env_o.cfg.allow_tx_err = 1;
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        set_format(8, ODVE_UART_PAR_EVEN, ODVE_UART_STOP1);
        for (int k = 0; k < 4; k++) begin
            send_err(3, k);
            send(4);
        end
        send(30, 30, 40);
        wait_drain();
        set_format(7, ODVE_UART_PAR_ODD, ODVE_UART_STOP2);
        send(30, 30, 40);
        wait_drain();
        set_format(5, ODVE_UART_PAR_MARK, ODVE_UART_STOP1_5);
        send(30, 30, 40);
        wait_drain();
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.scb_o.n_pe < 3 || env_o.scb_o.n_fe < 3 || env_o.scb_o.n_brk < 3 || env_o.agt.mon.n_glitch[0] < 3)
            `uvm_error(get_name(), $sformatf("injected errors not all observed: %0d parity, %0d framing, %0d breaks, %0d glitches (>= 3 each expected)",
                                             env_o.scb_o.n_pe, env_o.scb_o.n_fe, env_o.scb_o.n_brk, env_o.agt.mon.n_glitch[0]))
        if (env_o.scb_o.n_echo != env_o.scb_o.n_tx_ok)
            `uvm_error(get_name(), $sformatf("%0d good characters, %0d echoes", env_o.scb_o.n_tx_ok, env_o.scb_o.n_echo))
    endfunction
endclass : err_test
