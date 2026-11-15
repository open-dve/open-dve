// Register Write / Register Read (5-bit address) and Register 0 Write:
// every register 0..31 of both slaves written, read back, then a random mix
// of the three commands. REQ-RFFE-010..012.
class reg_test extends base_test;
    `uvm_component_utils(reg_test)

    function new(string name = "reg_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_rffe_dir_seq  d = dir_seq("d");
        odve_rffe_base_seq r = rand_seq("r", 60, 7'b0000111);
        bit [7:0] v[];
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (r.usids[k])
            for (int a = 0; a < 32; a++) begin
                bytes(1, v);
                void'(d.addw(ODVE_RFFE_REG_WR, r.usids[k], 16'(a), v));
            end
        foreach (r.usids[k])
            for (int a = 0; a < 32; a++) void'(d.add(ODVE_RFFE_REG_RD, r.usids[k], 16'(a), 1));
        run_seq(d);
        run_seq(r);
        phase.drop_objection(this);
    endtask : run_phase
endclass : reg_test
