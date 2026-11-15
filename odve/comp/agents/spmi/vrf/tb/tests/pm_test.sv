// Power-management commands: Sleep, Shutdown, Wakeup and Reset to each
// slave, each followed by a read of its power-state register (0x40); Reset
// must also clear the registers written before it, the other slave must
// keep its state and registers. Then a random mix of every command. Every
// PM command must be ACKed (scoreboard), the master must see the ACK too.
// REQ-SPMI-050..054.
class pm_test extends base_test;
    `uvm_component_utils(pm_test)

    function new(string name = "pm_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spmi_dir_seq  d = dir_seq("d");
        odve_spmi_base_seq r = rand_seq("r", 80, 11'h7FF);
        odve_spmi_item     pmc[$];
        odve_spmi_kind_e   order[5] = '{ODVE_SPMI_SLEEP, ODVE_SPMI_WAKEUP, ODVE_SPMI_SHUTDOWN, ODVE_SPMI_WAKEUP, ODVE_SPMI_SLEEP};
        bit [7:0]          v[];
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (r.sids[k]) begin
            bytes(16, v);
            void'(d.addw(ODVE_SPMI_EXT_WR, r.sids[k], 16'h0000, v));
            foreach (order[i]) begin
                pmc.push_back(d.add(order[i], r.sids[k], 16'h0000, 0));
                void'(d.add(ODVE_SPMI_EXT_RD, r.sids[k], 16'h0040, 1));
            end
            pmc.push_back(d.add(ODVE_SPMI_RESET, r.sids[k], 16'h0000, 0));
            void'(d.add(ODVE_SPMI_EXT_RD, r.sids[k], 16'h0000, 16));   // cleared
            void'(d.add(ODVE_SPMI_EXT_RD, r.sids[k], 16'h0040, 1));    // ACTIVE
        end
        void'(d.add(ODVE_SPMI_EXT_RD, r.sids[0], 16'h0038, 9));        // the other slave untouched
        run_seq(d);
        foreach (pmc[i])
            if (!pmc[i].ack) `uvm_error(get_name(), $sformatf("master saw %s: expected ACK", pmc[i].convert2string()))
        run_seq(r);
        phase.drop_objection(this);
        if (env_o.scb_o.n_pm == 0) `uvm_error(get_name(), "no PM command observed")
    endtask : run_phase
endclass : pm_test
