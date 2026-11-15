// Extended Register Write / Read: 8-bit address, 1..16 bytes, random over
// both slaves. REQ-SPMI-013, 014.
class ext_test extends base_test;
    `uvm_component_utils(ext_test)

    function new(string name = "ext_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spmi_base_seq r = rand_seq("r", 60, 11'h018);
        super.run_phase(phase);
        phase.raise_objection(this);
        run_seq(r);
        phase.drop_objection(this);
    endtask : run_phase
endclass : ext_test
