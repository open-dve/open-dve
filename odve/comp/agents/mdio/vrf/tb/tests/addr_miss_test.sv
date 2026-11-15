// Frames to PHY/port addresses nobody answers (0, 31, 30, and the first
// address of the bus + 8), Clause 22 and Clause 45, and to MMDs that are not
// present on a responding port: no answer, the line stays pulled up (reads
// FFFF), writes change nothing - checked by reading the responding PHYs'
// registers after the same writes.
class addr_miss_test extends base_test;
    `uvm_component_utils(addr_miss_test)

    function new(string name = "addr_miss_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_mdio_base_seq s = odve_mdio_base_seq::type_id::create("s");
        bit [4:0] miss[$];
        bit [4:0] hit = env_o.cc_o.addrs[0];
        odve_mdio_item no[$], yes[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        miss = '{5'd0, env_o.cc_o.miss_addr(0), env_o.cc_o.miss_addr(1), 5'(env_o.cc_o.addrs[0] + 8)};
        // known state at the responding PHY
        s.c22_wr(hit, 5'd4, 16'h1111);
        s.c45_addr(hit, ODVE_MDIO_MMD_PMA, 16'h8001);  s.c45_wr(hit, ODVE_MDIO_MMD_PMA, 16'h2222);
        foreach (miss[i]) begin
            s.c22_wr(miss[i], 5'd4, u16());
            no.push_back(s.push(ODVE_MDIO_C22_RD, miss[i], 5'd2));
            no.push_back(s.push(ODVE_MDIO_C22_RD, miss[i], 5'd4));
            s.c45_addr(miss[i], ODVE_MDIO_MMD_PMA, 16'h8001);
            s.c45_wr(miss[i], ODVE_MDIO_MMD_PMA, u16());
            no.push_back(s.push(ODVE_MDIO_C45_RD, miss[i], ODVE_MDIO_MMD_PMA));
            no.push_back(s.push(ODVE_MDIO_C45_RINC, miss[i], ODVE_MDIO_MMD_PCS));
        end
        // absent MMDs on the responding port
        for (int d = 0; d < 32; d += 5) begin
            if (5'(d) inside {ODVE_MDIO_MMD_PMA, ODVE_MDIO_MMD_PCS}) continue;
            s.c45_addr(hit, 5'(d), 16'h8001);
            s.c45_wr(hit, 5'(d), u16());
            no.push_back(s.push(ODVE_MDIO_C45_RD, hit, 5'(d)));
        end
        // the responding PHY is unchanged
        yes.push_back(s.push(ODVE_MDIO_C22_RD, hit, 5'd4));
        yes.push_back(s.push(ODVE_MDIO_C45_RD, hit, ODVE_MDIO_MMD_PMA));
        run_seq(s);
        foreach (no[i]) expect_rd(no[i], 0, 16'hFFFF);
        expect_rd(yes[0], 1, 16'h1111);
        expect_rd(yes[1], 1, 16'h2222);
        phase.drop_objection(this);
    endtask : run_phase
endclass : addr_miss_test
