// Writes a few registers, then reads the file back: the scoreboard checks
// every read against what was written.
class read_test extends base_test;
    `uvm_component_utils(read_test)

    function new(string name = "read_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_apb_write_seq wr = odve_apb_write_seq::type_id::create("wr");
        odve_apb_read_seq  rd = odve_apb_read_seq::type_id::create("rd");
        super.run_phase(phase);
        phase.raise_objection(this);
        wr.n = 8;
        run_seq(wr);
        rd.n = 16;
        run_seq(rd);
        phase.drop_objection(this);
    endtask : run_phase
endclass : read_test
