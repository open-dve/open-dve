// Everything at once, back to back (no idle between sequences): all kinds,
// both slaves, 10% broadcast writes, 10% accesses beyond the implemented
// registers. Run with each primary slave (+rffe_slave=dut|mem|seq).
// REQ-RFFE-018, 040, 041.
class rand_test extends base_test;
    `uvm_component_utils(rand_test)

    function new(string name = "rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_rffe_base_seq r = rand_seq("r", 150, 7'h7F);
        super.run_phase(phase);
        phase.raise_objection(this);
        env_o.cfg.idle_halfs = 0;
        r.bcast_pct = 10;
        r.oor_pct   = 10;
        run_seq(r);
        phase.drop_objection(this);
    endtask : run_phase
endclass : rand_test
