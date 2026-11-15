// Passive observer of the MDIO bus. Decodes every frame bit by bit at the
// MDC rising edges (where both ends sample MDIO), publishes one item per
// frame on item_collected_port and feeds the coverage. It sees the line and
// every driver's enable, so it checks who drives what:
//
//   MDIO_PRE   fewer than cfg.pre_min preamble ones before ST
//   MDIO_OP    Clause 22 frame with an undefined OP (00/11)
//   MDIO_TA    write-type TA not 10 driven by the STA; read TA[1] not released
//   MDIO_DIR   STA drives during a read's TA/data, or not during a write's
//   MDIO_RESP  read answered for part of the data only / undriven 0
//   MDIO_IDLE  a PHY drives MDIO outside the TA[0]+data of a read frame
//   MDIO_CONT  two drivers enabled at one sampling edge
//   MDIO_SETUP / MDIO_HOLD  MDIO changed within cfg.t_su before / (STA bits)
//              cfg.t_hold after an MDC rising edge
//
// An unanswered read (no PHY at that address) is not an error here: the
// item says resp=0 and data=FFFF (the pull-up), and the scoreboard decides.
class odve_mdio_mon extends uvm_monitor;
    `uvm_component_utils(odve_mdio_mon)

    uvm_analysis_port #(odve_mdio_item) item_collected_port;
    virtual odve_mdio_if vif;
    odve_mdio_cfg        cfg;
    int unsigned n_seen = 0;
    int unsigned n_err  = 0;

    // per-bit snapshot taken by get_bit()
    protected bit s_sta_oe, s_phy_oe;
    protected odve_mdio_item cur;

    // timing check state
    protected realtime t_chg = -1.0, t_rise = -1.0;
    protected bit      rise_sta = 0;

    // Functional coverage: the covergroup is declared in odve_mdio_agent_pkg
    // (package scope, `ifdef ODVE_COV_NATIVE); with FCOV=1 the build generates
    // odve_cov_pkg::odve_cov_odve_mdio_cg from it and these two macros are
    // the whole hook. Without FCOV=1 both expand to nothing.
    `odve_cov_create(odve_mdio_cg)

    function new(string name = "odve_mdio_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    protected function void err(string id, string msg);
        n_err++;
        if (cur != null) cur.n_err++;
        `uvm_error(id, msg)
    endfunction

    // Next MDC rising edge: the line value and who drove it.
    protected task get_bit(output bit b);
        int n;
        @(posedge vif.mdc);
        b        = vif.mdio;
        s_sta_oe = vif.sta_oe;
        s_phy_oe = vif.phy_oe | vif.dut_oe;
        n = int'(vif.sta_oe) + int'(vif.phy_oe) + int'(vif.dut_oe);
        if (n > 1)
            err("MDIO_CONT", $sformatf("%0d drivers on MDIO at one MDC edge (sta_oe=%0b phy_oe=%0b dut_oe=%0b)", n, vif.sta_oe, vif.phy_oe, vif.dut_oe));
    endtask

    protected task get_field(int unsigned n, output bit [15:0] v);
        bit b;
        v = '0;
        repeat (n) begin
            get_bit(b);
            v = {v[14:0], b};
        end
    endtask

    protected task frames();
        bit          b;
        bit [15:0]   v;
        bit [1:0]    st, op;
        int unsigned ones;
        odve_mdio_item tr;
        forever begin
            cur  = null;
            ones = 0;
            // PRE / IDLE: ones until the first 0, which is ST[1]
            forever begin
                get_bit(b);
                if (s_phy_oe) err("MDIO_IDLE", "a PHY drives MDIO between frames");
                if (!b) break;
                ones++;
            end
            tr = odve_mdio_item::type_id::create("tr");
            cur = tr;
            tr.pre_len = ones;
            get_bit(b);  st = {1'b0, b};
            get_field(2, v); op = v[1:0];
            get_field(5, v); tr.phyad = v[4:0];
            get_field(5, v); tr.regad = v[4:0];
            tr.kind   = odve_mdio_item::decode(st, op);
            tr.bad_op = op;
            if (ones < cfg.pre_min)
                err("MDIO_PRE", $sformatf("preamble of %0d ones, at least %0d expected: %s", ones, cfg.pre_min, tr.convert2string()));
            if (tr.kind == ODVE_MDIO_C22_BAD)
                err("MDIO_OP", $sformatf("Clause 22 frame with undefined OP=%02b", op));
            if (tr.is_read()) begin
                // TA[1]: STA released, nobody drives, the line is pulled up
                get_bit(b);
                if (s_sta_oe || s_phy_oe || !b)
                    err("MDIO_TA", $sformatf("read TA[1] must be Z (sta_oe=%0b phy_oe=%0b mdio=%0b)", s_sta_oe, s_phy_oe, b));
                // TA[0]: the addressed PHY drives 0, else the pull-up leaves 1
                get_bit(b);
                if (s_sta_oe) err("MDIO_DIR", "STA drives MDIO in a read's TA[0]");
                tr.resp = !b;
                tr.ta   = 2'b10;
                if (!b && !s_phy_oe) err("MDIO_RESP", "TA[0]=0 but no PHY drives");
                if (b && s_phy_oe)   err("MDIO_RESP", "a PHY drives TA[0] high");
                for (int i = 15; i >= 0; i--) begin
                    get_bit(b);
                    tr.data[i] = b;
                    if (s_sta_oe) err("MDIO_DIR", $sformatf("STA drives MDIO in read data bit %0d", i));
                    if (tr.resp && !s_phy_oe) err("MDIO_RESP", $sformatf("read data bit %0d not driven by the PHY that answered TA", i));
                    if (!tr.resp && s_phy_oe) err("MDIO_RESP", $sformatf("read data bit %0d driven although TA[0] was not answered", i));
                end
            end else begin
                bit all_sta = 1;
                get_bit(b); tr.ta[1] = b; all_sta &= s_sta_oe;
                get_bit(b); tr.ta[0] = b; all_sta &= s_sta_oe;
                if (tr.ta != 2'b10 || !all_sta)
                    err("MDIO_TA", $sformatf("write-type TA=%02b (driven by the STA: %0b), 10 expected: %s", tr.ta, all_sta, tr.convert2string()));
                for (int i = 15; i >= 0; i--) begin
                    get_bit(b);
                    tr.data[i] = b;
                    if (!s_sta_oe) err("MDIO_DIR", $sformatf("STA does not drive write data bit %0d", i));
                end
            end
            n_seen++;
            `uvm_info(get_name(), tr.convert2string(), UVM_HIGH)
            `odve_cov_sample(odve_mdio_cg, int'(tr.kind), int'(tr.phyad), int'(tr.regad), tr.resp, int'(tr.pre_len), !tr.is_c45(), tr.is_c45(), tr.is_read())
            item_collected_port.write(tr);
        end
    endtask

    // Setup/hold around the MDC rising edges, from the times MDIO changes.
    protected task timing();
        fork
            forever begin
                @(vif.mdio);
                if (t_rise >= 0.0 && rise_sta && ($realtime - t_rise) < cfg.t_hold)
                    err("MDIO_HOLD", $sformatf("MDIO changed %0t after the MDC rising edge of an STA-driven bit (hold %0t)", $realtime - t_rise, cfg.t_hold));
                t_chg = $realtime;
            end
            forever begin
                @(posedge vif.mdc);
                if (t_chg >= 0.0 && ($realtime - t_chg) < cfg.t_su)
                    err("MDIO_SETUP", $sformatf("MDIO changed %0t before the MDC rising edge (setup %0t)", $realtime - t_chg, cfg.t_su));
                t_rise   = $realtime;
                rise_sta = vif.sta_oe;
            end
        join
    endtask

    virtual task run_phase(uvm_phase phase);
        wait (vif.rst_n === 1'b1);
        fork
            frames();
            timing();
        join
    endtask

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d frames observed, %0d protocol violations", n_seen, n_err), UVM_LOW)
    endfunction
endclass
