// Clause 45 on every responding port, MMDs 1 and 3: the read-only device
// registers, address + write / address + read of the RW window and of the
// control register, a write to an unimplemented register (reads 0), and an
// MMD that is not there (DEVAD 2: no answer).
class c45_test extends base_test;
    `uvm_component_utils(c45_test)

    function new(string name = "c45_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_mdio_base_seq s = odve_mdio_base_seq::type_id::create("s");
        bit [4:0] devs[2] = '{ODVE_MDIO_MMD_PMA, ODVE_MDIO_MMD_PCS};
        odve_mdio_item ids[$], absent[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (env_o.cc_o.addrs[k]) begin
            bit [4:0] a = env_o.cc_o.addrs[k];
            foreach (devs[d]) begin
                s.c45_addr(a, devs[d], 16'd2);  ids.push_back(s.push(ODVE_MDIO_C45_RD, a, devs[d]));
                s.c45_addr(a, devs[d], 16'd5);  s.c45_rd(a, devs[d]);
                s.c45_addr(a, devs[d], 16'd1);  s.c45_rd(a, devs[d]);
                s.c45_addr(a, devs[d], 16'd0);  s.c45_wr(a, devs[d], u16());  s.c45_rd(a, devs[d]);
                for (int i = 0; i < ODVE_MDIO_NRW45; i++) begin
                    s.c45_addr(a, devs[d], 16'h8000 + 16'(i));
                    s.c45_wr(a, devs[d], u16());
                end
                for (int i = ODVE_MDIO_NRW45 - 1; i >= 0; i--) begin
                    s.c45_addr(a, devs[d], 16'h8000 + 16'(i));
                    s.c45_rd(a, devs[d]);
                end
                s.c45_addr(a, devs[d], 16'h0100);  s.c45_wr(a, devs[d], 16'hBEEF);  s.c45_rd(a, devs[d]);
                s.c45_wr(a, devs[d], 16'h1234);    s.c45_rd(a, devs[d]);           // 0x0100 still: 0
            end
            s.c45_addr(a, 5'd2, 16'h0000);  absent.push_back(s.push(ODVE_MDIO_C45_RD, a, 5'd2));
        end
        run_seq(s);
        foreach (ids[i])    expect_rd(ids[i], 1, ODVE_MDIO_ID1);
        foreach (absent[i]) expect_rd(absent[i], 0, 16'hFFFF);
        phase.drop_objection(this);
    endtask : run_phase
endclass : c45_test
