// Everything at once, back to back (no idle between sequences): all kinds
// including the PM commands, both slaves, 10% accesses beyond the
// implemented registers. Run with each primary slave (+spmi_slave=dut|mem|seq).
// REQ-SPMI-018, 040, 041.
class rand_test extends base_test;
    `uvm_component_utils(rand_test)

    function new(string name = "rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spmi_base_seq r = rand_seq("r", 150, 11'h7FF);
        super.run_phase(phase);
        phase.raise_objection(this);
        env_o.cfg.idle_halfs = 0;
        r.oor_pct   = 10;
        run_seq(r);
        phase.drop_objection(this);
    endtask : run_phase
endclass : rand_test
