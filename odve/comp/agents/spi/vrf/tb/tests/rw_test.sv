// Random register reads and writes to both slaves in their default formats
// (cs0: mode 0, MSB first, 8-bit; cs1: mode 3, LSB first, 16-bit).
class rw_test extends base_test;
    `uvm_component_utils(rw_test)
    function new(string name = "rw_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spi_reg_seq s = reg_seq("rw");
        super.run_phase(phase);
        phase.raise_objection(this);
        s.n = 60;
        s.max_words = 9;
        run_seq(s);
        phase.drop_objection(this);
    endtask : run_phase
endclass : rw_test
