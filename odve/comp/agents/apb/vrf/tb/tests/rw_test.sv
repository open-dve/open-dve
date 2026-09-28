// Mixed reads and writes, out-of-range allowed: the widest traffic of the three.
class rw_test extends base_test;
    `uvm_component_utils(rw_test)

    function new(string name = "rw_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_apb_rw_seq rw = odve_apb_rw_seq::type_id::create("rw");
        super.run_phase(phase);
        phase.raise_objection(this);
        rw.n = 40;
        rw.allow_oor = 1;
        run_seq(rw);
        phase.drop_objection(this);
    endtask : run_phase
endclass : rw_test
