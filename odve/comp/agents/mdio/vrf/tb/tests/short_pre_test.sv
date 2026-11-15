// Preamble length. The PHY (no preamble suppression) needs 32 ones before
// ST; what it counts is every 1 on MDIO since the last frame, i.e. the idle
// cycles before the frame plus the driven preamble. Frames with fewer must
// be ignored (a read unanswered, a write not applied) and the monitor must
// flag each of them (MDIO_PRE, counted here through a report catcher).
// Exactly 32 (e.g. 31 driven + 1 idle) and longer preambles are accepted.
class short_pre_test extends base_test;
    `uvm_component_utils(short_pre_test)

    err_catcher  ctch;
    int unsigned n_short = 0;

    function new(string name = "short_pre_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ctch = new("ctch");
        ctch.ids.push_back("MDIO_PRE");
        uvm_report_cb::add(null, ctch);
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_mdio_base_seq s = odve_mdio_base_seq::type_id::create("s");
        bit [4:0] a = env_o.cc_o.addrs[0];
        int unsigned pre[6] = '{0, 1, 16, 30, 31, 40};   // driven ones; +1 idle from the frame before
        odve_mdio_item it, rd[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        s.c22_wr(a, 5'd6, 16'h0000);
        s.c45_addr(a, ODVE_MDIO_MMD_PMA, 16'h8002);
        s.c45_wr(a, ODVE_MDIO_MMD_PMA, 16'h0000);
        foreach (pre[i]) begin
            bit [15:0] d = 16'h1000 + 16'(i);
            bit ok = (pre[i] + 1 >= 32);
            s.pre_len = pre[i];
            s.c22_wr(a, 5'd6, d);                                     // applied only if ok
            it = s.push(ODVE_MDIO_C22_RD, a, 5'd6);  rd.push_back(it);   // answered only if ok
            s.c45_wr(a, ODVE_MDIO_MMD_PMA, d);                        // the address frame is the full-preamble one before
            if (!ok) n_short += 3;
            s.pre_len = 32;
            it = s.push(ODVE_MDIO_C22_RD, a, 5'd6);  rd.push_back(it);   // what the write left
            s.c45_addr(a, ODVE_MDIO_MMD_PMA, 16'h8002);
            it = s.push(ODVE_MDIO_C45_RD, a, ODVE_MDIO_MMD_PMA);  rd.push_back(it);
        end
        run_seq(s);
        begin
            bit [15:0] last22 = 16'h0000, last45 = 16'h0000;
            foreach (pre[i]) begin
                bit [15:0] d = 16'h1000 + 16'(i);
                bit ok = (pre[i] + 1 >= 32);
                if (ok) begin last22 = d; last45 = d; end
                expect_rd(rd[3 * i], ok, ok ? d : 16'hFFFF);
                expect_rd(rd[3 * i + 1], 1, last22);
                expect_rd(rd[3 * i + 2], 1, last45);
            end
        end
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (ctch.count("MDIO_PRE") != n_short)
            `uvm_error(get_name(), $sformatf("monitor flagged %0d short preambles, %0d were sent", ctch.count("MDIO_PRE"), n_short))
        else
            `uvm_info(get_name(), $sformatf("monitor flagged all %0d short preambles", n_short), UVM_LOW)
    endfunction
endclass : short_pre_test
