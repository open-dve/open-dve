// Parity error injection: 40% of the sequences (every kind, PM commands
// too) have one inverted parity bit (command, address or write data frame).
// The monitor must flag each one (counted against the injections, not
// reported as errors here); the slave must NACK the write (or stay silent on
// a bad command frame), ignore a bad command/address and drop a bad data
// frame and the ones after it - the scoreboard's ACK check, model and read
// checks show whether it did. REQ-SPMI-030..033.
class par_err_test extends base_test;
    `uvm_component_utils(par_err_test)

    function new(string name = "par_err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spmi_base_seq r = rand_seq("r", 100, 11'h7FF);
        super.run_phase(phase);
        phase.raise_objection(this);
        env_o.cfg.chk_parity = 0;
        r.inj_pct = 40;
        run_seq(r);
        env_o.scb_o.exp_par_err = r.n_inj;
        `uvm_info(get_name(), $sformatf("%0d sequences with an injected parity error", r.n_inj), UVM_LOW)
        if (r.n_inj == 0) `uvm_error(get_name(), "no parity error was injected")
        phase.drop_objection(this);
    endtask : run_phase
endclass : par_err_test
