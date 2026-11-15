// Register Write / Register Read (5-bit address) and Register 0 Write:
// every register 0..31 of both slaves written, read back, then a random mix
// of the three commands. REQ-SPMI-010..012.
class reg_test extends base_test;
    `uvm_component_utils(reg_test)

    function new(string name = "reg_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spmi_dir_seq  d = dir_seq("d");
        odve_spmi_base_seq r = rand_seq("r", 60, 11'h007);
        bit [7:0] v[];
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (r.sids[k])
            for (int a = 0; a < 32; a++) begin
                bytes(1, v);
                void'(d.addw(ODVE_SPMI_REG_WR, r.sids[k], 16'(a), v));
            end
        foreach (r.sids[k])
            for (int a = 0; a < 32; a++) void'(d.add(ODVE_SPMI_REG_RD, r.sids[k], 16'(a), 1));
        run_seq(d);
        run_seq(r);
        phase.drop_objection(this);
    endtask : run_phase
endclass : reg_test
