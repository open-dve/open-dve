// Writes a few registers, then reads the file back: the scoreboard checks
// every read against what was written.
class read_test extends base_test;
    `uvm_component_utils(read_test)
    odve_rand rng;

    function new(string name = "read_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rng = new(get_full_name());
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        odve_apb_write_seq wr = odve_apb_write_seq::type_id::create("wr");
        odve_apb_read_seq  rd = odve_apb_read_seq::type_id::create("rd");
        super.run_phase(phase);
        // the same line on every simulator for the same SEED
        `uvm_info(get_name(), $sformatf("odve_rand: SEED %0d, first draw %0d", odve_rand::run_seed(), rng.u32()), UVM_NONE)
        phase.raise_objection(this);
        wr.n = 8;
        run_seq(wr);
        rd.n = 16;
        run_seq(rd);
        phase.drop_objection(this);
    endtask : run_phase
endclass : read_test
