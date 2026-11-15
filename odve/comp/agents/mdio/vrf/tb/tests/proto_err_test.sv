// Error injection by the STA: write-type frames with a wrong turnaround
// (TA = 11, 00, 01 instead of 10) and Clause 22 frames with an undefined
// opcode (00, 11). The PHY must ignore all of them (registers unchanged,
// checked by the reads after) and the monitor must flag each one
// (MDIO_TA / MDIO_OP, counted through a report catcher).
class proto_err_test extends base_test;
    `uvm_component_utils(proto_err_test)

    err_catcher  ctch;
    int unsigned n_ta = 0, n_op = 0;

    function new(string name = "proto_err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ctch = new("ctch");
        ctch.ids.push_back("MDIO_TA");
        ctch.ids.push_back("MDIO_OP");
        uvm_report_cb::add(null, ctch);
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_mdio_base_seq s = odve_mdio_base_seq::type_id::create("s");
        bit [4:0] a = env_o.cc_o.addrs[0];
        bit [1:0] bad_ta[3] = '{2'b11, 2'b00, 2'b01};
        bit [1:0] bad_op[2] = '{2'b00, 2'b11};
        odve_mdio_item it, rd[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        s.c22_wr(a, 5'd7, 16'h7777);
        s.c45_addr(a, ODVE_MDIO_MMD_PCS, 16'h8004);
        s.c45_wr(a, ODVE_MDIO_MMD_PCS, 16'h4444);
        foreach (bad_ta[i]) begin
            it = s.push(ODVE_MDIO_C22_WR, a, 5'd7, 16'hDEAD);    it.ta = bad_ta[i];  n_ta++;
            it = s.push(ODVE_MDIO_C45_WR, a, ODVE_MDIO_MMD_PCS, 16'hDEAD);  it.ta = bad_ta[i];  n_ta++;
            it = s.push(ODVE_MDIO_C45_ADDR, a, ODVE_MDIO_MMD_PCS, 16'h0000); it.ta = bad_ta[i];  n_ta++;
            rd.push_back(s.push(ODVE_MDIO_C22_RD, a, 5'd7));
            rd.push_back(s.push(ODVE_MDIO_C45_RD, a, ODVE_MDIO_MMD_PCS));
        end
        foreach (bad_op[i]) begin
            it = s.push(ODVE_MDIO_C22_BAD, a, 5'd7, 16'hBAD0);  it.bad_op = bad_op[i];  n_op++;
            rd.push_back(s.push(ODVE_MDIO_C22_RD, a, 5'd7));
        end
        run_seq(s);
        for (int i = 0; i < 3; i++) begin
            expect_rd(rd[2 * i], 1, 16'h7777);
            expect_rd(rd[2 * i + 1], 1, 16'h4444);
        end
        expect_rd(rd[6], 1, 16'h7777);
        expect_rd(rd[7], 1, 16'h7777);
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (ctch.count("MDIO_TA") != n_ta || ctch.count("MDIO_OP") != n_op)
            `uvm_error(get_name(), $sformatf("monitor flagged %0d bad TA / %0d bad OP, %0d / %0d were sent", ctch.count("MDIO_TA"), ctch.count("MDIO_OP"), n_ta, n_op))
        else
            `uvm_info(get_name(), $sformatf("monitor flagged all %0d bad TA and %0d bad OP frames", n_ta, n_op), UVM_LOW)
    endfunction
endclass : proto_err_test
