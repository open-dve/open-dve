// Back-to-back frames: no idle cycle between frames (the next preamble
// starts on the MDC cycle after the last data bit, also right after a read
// whose data the PHY drove), directed and random, both clauses.
class b2b_test extends base_test;
    `uvm_component_utils(b2b_test)

    function new(string name = "b2b_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_mdio_base_seq s  = odve_mdio_base_seq::type_id::create("s");
        odve_mdio_rand_seq rs = odve_mdio_rand_seq::type_id::create("rs");
        bit [4:0] a = env_o.cc_o.addrs[0];
        odve_mdio_item r[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        s.idle = 0;
        s.c22_wr(a, 5'd5, 16'hA5A5);
        r.push_back(s.push(ODVE_MDIO_C22_RD, a, 5'd5));
        r.push_back(s.push(ODVE_MDIO_C22_RD, a, 5'd5));
        r.push_back(s.push(ODVE_MDIO_C22_RD, a, 5'd2));
        s.c45_addr(a, ODVE_MDIO_MMD_PCS, 16'h8003);
        s.c45_wr(a, ODVE_MDIO_MMD_PCS, 16'h5A5A);
        s.c45_addr(a, ODVE_MDIO_MMD_PCS, 16'h8003);
        r.push_back(s.push(ODVE_MDIO_C45_RINC, a, ODVE_MDIO_MMD_PCS));
        r.push_back(s.push(ODVE_MDIO_C45_RD, a, ODVE_MDIO_MMD_PCS));
        run_seq(s);
        expect_rd(r[0], 1, 16'hA5A5);
        expect_rd(r[1], 1, 16'hA5A5);
        expect_rd(r[2], 1, ODVE_MDIO_ID1);
        expect_rd(r[3], 1, 16'h5A5A);
        expect_rd(r[4], 1, 16'h0000);
        rs.n        = 60;
        rs.addrs    = env_o.cc_o.addrs;
        rs.miss_pct = 10;
        rs.max_idle = 0;
        run_seq(rs);
        phase.drop_objection(this);
    endtask : run_phase
endclass : b2b_test
