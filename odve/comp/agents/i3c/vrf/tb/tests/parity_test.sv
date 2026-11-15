// Parity errors. A private write whose third byte carries a wrong T-bit:
// the target must drop that byte and the rest of the transfer (the
// scoreboard's model does the same, and the read-back compares), and report
// it in GETSTATUS[5], which reading clears. Then an ENTDAA round whose
// address parity bit is wrong: the winner must NACK it and win the next
// round. The monitor sees every injected error (counted, not a UVM_ERROR:
// cfg.perr_is_error = 0) - the test checks the count.
class parity_test extends base_test;
    `uvm_component_utils(parity_test)

    function new(string name = "parity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_i3c_item it;
        bit [6:0]     q[$];
        int unsigned  n_inj = 0;
        bit [7:0]     none[$];
        super.run_phase(phase);
        env_o.cfg.perr_is_error = 0;
        phase.raise_objection(this);
        assign_all(pool);
        das(q);
        foreach (q[i]) begin
            rand_wr(q[i], 0, 8);                                         // known contents
            priv_wr(q[i], '{8'h02, 8'hA1, 8'hB2, 8'hC3, 8'hD4}, 2);     // byte 2 (0xB2) has a bad T-bit
            n_inj++;
            priv_wr(q[i], '{8'h00});
            priv_rd(q[i], 8, it);                                        // 0xA1 written, 0xB2.. not
            ccc_dr(I3C_CCC_GETSTATUS, q[i], it);
            if (it.data.size() == 2 && !it.data[1][5]) `uvm_error(get_name(), "GETSTATUS[5] (protocol error) not set after a parity error")
            ccc_dr(I3C_CCC_GETSTATUS, q[i], it);
            if (it.data.size() == 2 && it.data[1][5]) `uvm_error(get_name(), "GETSTATUS[5] still set after being read")
            priv_wr(q[i], '{8'h0A, 8'h5A}, 0);                          // bad pointer byte: nothing happens
            n_inj++;
            priv_wr(q[i], '{8'h0A});
            priv_rd(q[i], 1, it);
        end
        ccc_bc(I3C_CCC_RSTDAA, none);
        entdaa(pool, it, 0);                                             // round 0: wrong parity -> NACK
        n_inj++;
        if (it.daa_ack.size() == 0 || it.daa_ack[0]) `uvm_error(get_name(), "ENTDAA address with wrong parity was ACKed")
        if (it.daa_id.size() != env_o.scb_o.n_online() + 1)
            `uvm_error(get_name(), $sformatf("ENTDAA with one bad round: %0d rounds, expected %0d", it.daa_id.size(), env_o.scb_o.n_online() + 1))
        das(q);
        foreach (q[i]) priv_rd(q[i], 2, it);
        if (env_o.agt.mon.n_perr_seen != n_inj)
            `uvm_error(get_name(), $sformatf("monitor saw %0d parity error(s), %0d injected", env_o.agt.mon.n_perr_seen, n_inj))
        phase.drop_objection(this);
    endtask : run_phase
endclass : parity_test
