// Extended Register Write / Read Long: 16-bit address, 1..8 bytes, a fifth
// of them starting beyond the implemented registers (NRF on read, no write).
// REQ-RFFE-015, 016.
class extl_test extends base_test;
    `uvm_component_utils(extl_test)

    function new(string name = "extl_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_rffe_base_seq r = rand_seq("r", 60, 7'b1100000);
        super.run_phase(phase);
        phase.raise_objection(this);
        r.oor_pct = 20;
        run_seq(r);
        phase.drop_objection(this);
    endtask : run_phase
endclass : extl_test
