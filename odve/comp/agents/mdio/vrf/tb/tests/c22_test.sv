// Clause 22 on every responding PHY: reset values and the read-only status/ID
// registers, writes to every register (the read-only ones must not change),
// then all 32 registers read back.
class c22_test extends base_test;
    `uvm_component_utils(c22_test)

    function new(string name = "c22_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_mdio_base_seq s = odve_mdio_base_seq::type_id::create("s");
        bit [15:0] wr [32];
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (env_o.cc_o.addrs[k]) begin
            bit [4:0] a = env_o.cc_o.addrs[k];
            for (int r = 0; r < 4; r++) s.c22_rd(a, 5'(r));          // q[0..3]: reset values / IDs
            for (int r = 0; r < 32; r++) begin
                wr[r] = u16();
                s.c22_wr(a, 5'(r), wr[r]);
            end
            for (int r = 0; r < 32; r++) s.c22_rd(a, 5'(r));
        end
        run_seq(s);
        foreach (env_o.cc_o.addrs[k]) begin
            int b = k * 68;
            expect_rd(s.q[b + 0], 1, ODVE_MDIO_BMCR_RST);
            expect_rd(s.q[b + 1], 1, ODVE_MDIO_BMSR);
            expect_rd(s.q[b + 2], 1, ODVE_MDIO_ID1);
            expect_rd(s.q[b + 3], 1, ODVE_MDIO_ID2);
            expect_rd(s.q[b + 36 + 1], 1, ODVE_MDIO_BMSR);
            expect_rd(s.q[b + 36 + 2], 1, ODVE_MDIO_ID1);
            expect_rd(s.q[b + 36 + 3], 1, ODVE_MDIO_ID2);
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : c22_test
