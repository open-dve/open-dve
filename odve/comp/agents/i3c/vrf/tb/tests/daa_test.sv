// Dynamic Address Assignment. RSTDAA + ENTDAA: every target on the bus
// arbitrates with its 48-bit PID + BCR + DCR on the open-drain phase, the
// lowest wins each round (the scoreboard checks the order and the IDs).
// Then GETPID/GETBCR/GETDCR and a private write/read on each new address;
// a second ENTDAA with everyone assigned (no round answers); RSTDAA and an
// ENTDAA with another address pool: old addresses NACK, new ones work.
class daa_test extends base_test;
    `uvm_component_utils(daa_test)

    function new(string name = "daa_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task touch_all();
        bit [6:0]     q[$];
        odve_i3c_item it;
        das(q);
        foreach (q[i]) begin
            ccc_dr(I3C_CCC_GETPID, q[i], it);
            ccc_dr(I3C_CCC_GETBCR, q[i], it);
            ccc_dr(I3C_CCC_GETDCR, q[i], it);
            rand_wr(q[i], 3, 4);
            priv_rd(q[i], 4, it);
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_i3c_item it;
        bit [6:0]     p2[$] = '{7'h10, 7'h11, 7'h12};
        super.run_phase(phase);
        phase.raise_objection(this);
        assign_all(pool);
        touch_all();
        entdaa(pool, it);                      // nobody left without an address
        if (it.daa_id.size() != 0) `uvm_error(get_name(), $sformatf("second ENTDAA: %0d round(s) answered", it.daa_id.size()))
        assign_all(p2);
        foreach (pool[i]) begin
            priv_rd(pool[i], 1, it);           // the old addresses are gone
            if (it.ack) `uvm_error(get_name(), $sformatf("old address 0x%02h still ACKs after RSTDAA", pool[i]))
        end
        touch_all();
        phase.drop_objection(this);
    endtask : run_phase
endclass : daa_test
