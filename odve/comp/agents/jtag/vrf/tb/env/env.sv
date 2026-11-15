// Master agent (the JTAG host, always) and, per +jtag_slave, the RTL target
// (one TAP or a chain of two) or the slave agent in one of its two modes.
// The scoreboard watches the pins through the master agent's monitor; the
// slave agent has no monitor of its own (has_mon = 0).
class env extends uvm_env;
    `uvm_component_utils(env)

    cc              cc_o;
    odve_jtag_agent agt;       // master
    odve_jtag_cfg   cfg;
    odve_jtag_agent agt_s;     // slave agent, when +jtag_slave=mem|seq
    odve_jtag_cfg   cfg_s;
    scb             scb_o;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_jtag_if vif;
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_jtag_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "no virtual odve_jtag_if 'vif' in uvm_config_db (set it from top)")

        cfg = odve_jtag_cfg::type_id::create("cfg");
        cfg.role   = ODVE_JTAG_MASTER;
        cfg.vif    = vif;
        cfg.ir_len = 4 * cc_o.n_taps();
        uvm_config_db#(odve_jtag_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_jtag_agent::type_id::create("agt", this);

        if (cc_o.slave_is_agent()) begin
            cfg_s = odve_jtag_cfg::type_id::create("cfg_s");
            cfg_s.role           = ODVE_JTAG_SLAVE;
            cfg_s.slv_mode       = (cc_o.slave == "seq") ? ODVE_JTAG_SLV_SEQ : ODVE_JTAG_SLV_MEM;
            cfg_s.has_mon        = 0;
            cfg_s.vif            = vif;
            cfg_s.idcode         = cc_o.idcode(0);
            cfg_s.pins           = cc_o.pins(0);
            cfg_s.err_tdo_oe     = (cc_o.err == "oe");
            cfg_s.err_ir_capture = (cc_o.err == "ircap");
            uvm_config_db#(odve_jtag_cfg)::set(this, "agt_s", "cfg", cfg_s);
            agt_s = odve_jtag_agent::type_id::create("agt_s", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.jtag_imp);
        for (int unsigned k = 0; k < cc_o.n_taps(); k++) begin
            odve_jtag_tap_model m = odve_jtag_tap_model::type_id::create($sformatf("tap%0d", k));
            m.idcode = cc_o.idcode(k);
            m.pins   = cc_o.pins(k);
            scb_o.taps.push_back(m);
        end
    endfunction
endclass : env
