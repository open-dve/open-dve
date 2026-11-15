// Clause 45 post-read-increment-address: fill the RW window, set the address
// once and read it back as a block with OP=10; the address register must
// end one past the window (a plain read there returns 0, unimplemented).
// Then the 16-bit wrap: address FFFF, two post-increment reads - the second
// reads register 0 (control).
class c45_rinc_test extends base_test;
    `uvm_component_utils(c45_rinc_test)

    function new(string name = "c45_rinc_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_mdio_base_seq s = odve_mdio_base_seq::type_id::create("s");
        bit [4:0]  devs[2] = '{ODVE_MDIO_MMD_PMA, ODVE_MDIO_MMD_PCS};
        bit [15:0] v[ODVE_MDIO_NRW45];
        odve_mdio_item blk[$], after[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (env_o.cc_o.addrs[k]) begin
            bit [4:0] a = env_o.cc_o.addrs[k];
            foreach (devs[d]) begin
                for (int i = 0; i < ODVE_MDIO_NRW45; i++) begin
                    v[i] = u16();
                    s.c45_addr(a, devs[d], 16'h8000 + 16'(i));
                    s.c45_wr(a, devs[d], v[i]);
                end
                s.c45_addr(a, devs[d], 16'h8000);
                for (int i = 0; i < ODVE_MDIO_NRW45; i++) begin
                    blk.push_back(s.push(ODVE_MDIO_C45_RINC, a, devs[d]));
                    blk[$].data = v[i];      // the expectation, overwritten by the read
                end
                after.push_back(s.push(ODVE_MDIO_C45_RD, a, devs[d]));
                // wrap
                s.c45_addr(a, devs[d], 16'h0000);  s.c45_wr(a, devs[d], 16'h00A5);
                s.c45_addr(a, devs[d], 16'hFFFF);
                s.c45_rinc(a, devs[d]);
                s.c45_rinc(a, devs[d]);           // address 0: control = 00A5
                s.c45_rd(a, devs[d]);             // address 1: status
            end
        end
        begin
            bit [15:0] e[$];
            foreach (blk[i]) e.push_back(blk[i].data);
            run_seq(s);
            foreach (blk[i])   expect_rd(blk[i], 1, e[i]);
            foreach (after[i]) expect_rd(after[i], 1, 16'h0);
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : c45_rinc_test
