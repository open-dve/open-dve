// Private transfers to the dynamic address(es): random writes/reads
// (odve_i3c_priv_rand_seq), then the boundaries - the whole register file
// written in one transfer and read back in one (the target ends with T=0 on
// the last register), a read from the last two registers, one-byte reads
// the controller ends by abort, writes/reads without the 7'h7E header
// (S <addr> directly, arbitrated), back-to-back transfers, and transfers to
// an address nobody has (NACK).
class priv_test extends base_test;
    `uvm_component_utils(priv_test)

    function new(string name = "priv_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_i3c_item          it;
        bit [6:0]              q[$];
        bit [7:0]              b[$];
        odve_i3c_priv_rand_seq rs = odve_i3c_priv_rand_seq::type_id::create("rs");
        super.run_phase(phase);
        phase.raise_objection(this);
        assign_all(pool);
        das(q);

        rs.rng       = rng.spawn("rs");
        rs.tgt_addrs = q;
        rs.n         = 40;
        rs.max_len   = 10;
        rs.start(env_o.agt.sqr);

        foreach (q[i]) begin
            rand_wr(q[i], 0, NREGS);                 // whole file, pointer 0
            priv_rd(q[i], NREGS + 4, it);            // target ends at the last register
            if (!it.t_end || it.data.size() != NREGS)
                `uvm_error(get_name(), $sformatf("full read: %0d byte(s), t_end=%0b", it.data.size(), it.t_end))
            b = '{8'(NREGS - 2)};
            priv_wr(q[i], b);                        // pointer only
            priv_rd(q[i], 8, it);                    // two bytes, then T=0
            if (!it.t_end || it.data.size() != 2) `uvm_error(get_name(), "read of the last two registers did not end after 2 bytes")
            b = '{8'h05};
            priv_wr(q[i], b);
            priv_rd(q[i], 1, it);                    // the controller aborts after one byte
            if (it.t_end) `uvm_error(get_name(), "one-byte read from register 5 ended by the target")
            rand_wr(q[i], 7, 3);
            b = '{8'h07};
            priv_wr(q[i], b, -1, 0);                 // no 7E header
            priv_rd(q[i], 3, it, 0);
        end
        // nobody at 0x5A
        rand_wr(7'h5A, 0, 2);
        priv_rd(7'h5A, 2, it);
        if (it.ack) `uvm_error(get_name(), "read from 0x5A ACKed")
        phase.drop_objection(this);
    endtask : run_phase
endclass : priv_test
