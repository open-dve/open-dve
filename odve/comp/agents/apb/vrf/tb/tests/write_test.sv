// Writes only, including out-of-range addresses the slave must refuse with pslverr.
class write_test extends base_test;
    `uvm_component_utils(write_test)

    function new(string name = "write_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_apb_write_seq wr = odve_apb_write_seq::type_id::create("wr");
        super.run_phase(phase);
        phase.raise_objection(this);
        wr.n = 24;
        wr.allow_oor = 1;
        run_seq(wr);
        phase.drop_objection(this);
    endtask : run_phase
endclass : write_test
