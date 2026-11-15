// No Response Frames: reads of USIDs no slave answers to and of registers
// beyond the implemented ones must come back as all-zero frames (parity
// included) without a parity error; the master's read data must show it.
// REQ-RFFE-022, 023.
class nrf_test extends base_test;
    `uvm_component_utils(nrf_test)

    function new(string name = "nrf_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_rffe_dir_seq  d = dir_seq("d");
        odve_rffe_base_seq r = rand_seq("r", 30, 7'b1010100);   // reads only
        odve_rffe_item     it[$];
        bit [3:0]          absent[3] = '{4'h1, 4'h3, 4'hF};
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (absent[k]) begin
            it.push_back(d.add(ODVE_RFFE_REG_RD,  absent[k], 16'h0003, 1));
            it.push_back(d.add(ODVE_RFFE_EXT_RD,  absent[k], 16'h0010, 4));
            it.push_back(d.add(ODVE_RFFE_EXTL_RD, absent[k], 16'h0000, 8));
        end
        run_seq(d);
        foreach (it[i])
            if (it[i].nrf_mask != (16'hFFFF >> (16 - it[i].nbytes)))
                `uvm_error(get_name(), $sformatf("master read %s: expected every frame NRF", it[i].convert2string()))
        r.oor_pct = 100;
        run_seq(r);
        phase.drop_objection(this);
    endtask : run_phase
endclass : nrf_test
