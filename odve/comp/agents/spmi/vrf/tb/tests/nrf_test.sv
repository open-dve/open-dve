// No response: reads of SIDs no slave answers to and of registers beyond the
// power-state register must come back as No Response Frames (all nine bits
// 0, no parity error), and the master's read data must show it; writes and
// PM commands to an absent SID must see NACK (nobody drives the ACK bit,
// the parked line reads 0). The monitor's NACK check is off for this test.
// REQ-SPMI-022, 023, 025.
class nrf_test extends base_test;
    `uvm_component_utils(nrf_test)

    function new(string name = "nrf_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spmi_dir_seq  d = dir_seq("d");
        odve_spmi_base_seq r = rand_seq("r", 30, 11'h054);   // reads only
        odve_spmi_item     it[$];
        odve_spmi_item     wr[$];
        bit [3:0]          absent[3] = '{4'h1, 4'h3, 4'hF};
        bit [7:0]          v[];
        super.run_phase(phase);
        phase.raise_objection(this);
        env_o.cfg.chk_parity = 0;
        foreach (absent[k]) begin
            it.push_back(d.add(ODVE_SPMI_REG_RD,  absent[k], 16'h0003, 1));
            it.push_back(d.add(ODVE_SPMI_EXT_RD,  absent[k], 16'h0010, 4));
            it.push_back(d.add(ODVE_SPMI_EXTL_RD, absent[k], 16'h0000, 8));
            bytes(2, v);
            wr.push_back(d.addw(ODVE_SPMI_EXT_WR, absent[k], 16'h0010, v));
            wr.push_back(d.add(ODVE_SPMI_SLEEP,   absent[k], 16'h0000, 0));
        end
        run_seq(d);
        foreach (it[i])
            if (it[i].nrf_mask != (16'hFFFF >> (16 - it[i].nbytes)))
                `uvm_error(get_name(), $sformatf("master read %s: expected every frame NRF", it[i].convert2string()))
        foreach (wr[i])
            if (wr[i].ack) `uvm_error(get_name(), $sformatf("master saw %s: expected NACK", wr[i].convert2string()))
        r.oor_pct = 100;
        run_seq(r);
        phase.drop_objection(this);
    endtask : run_phase
endclass : nrf_test
