// Broadcast: half of all writes (every kind) go to USID 0 and must reach
// both slaves; reads per slave check it. REQ-RFFE-020.
class bcast_test extends base_test;
    `uvm_component_utils(bcast_test)

    function new(string name = "bcast_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_rffe_base_seq r = rand_seq("r", 80, 7'h7F);
        super.run_phase(phase);
        phase.raise_objection(this);
        r.bcast_pct = 50;
        run_seq(r);
        phase.drop_objection(this);
        if (env_o.scb_o.n_bcast == 0) `uvm_error(get_name(), "no broadcast write was sent")
    endtask : run_phase
endclass : bcast_test
