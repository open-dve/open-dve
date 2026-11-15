// Controller agent (always) and, per +i3c_target, the RTL target and/or the
// target agent on the same bus. The scoreboard watches the bus through the
// controller agent's monitor; the target agent has no monitor of its own
// (has_mon = 0), or every transfer would be observed twice.
class env extends uvm_env;
    `uvm_component_utils(env)

    cc             cc_o;
    odve_i3c_agent agt;       // controller
    odve_i3c_cfg   cfg;
    odve_i3c_agent agt_t;     // target agent, when +i3c_target=mem|seq|both
    odve_i3c_cfg   cfg_t;
    scb            scb_o;
    virtual odve_i3c_if vif;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_i3c_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "no virtual odve_i3c_if 'vif' in uvm_config_db (set it from top)")

        cfg = odve_i3c_cfg::type_id::create("cfg");
        cfg.role = ODVE_I3C_MASTER;
        cfg.vif  = vif;
        uvm_config_db#(odve_i3c_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_i3c_agent::type_id::create("agt", this);

        scb_o = scb::type_id::create("scb_o", this);
        if (cc_o.has_dut()) scb_o.m_dut = scb_o.add("dut", DUT_PID, DUT_BCR, DUT_DCR, DUT_SA);

        if (cc_o.has_tgt_agent()) begin
            cfg_t = odve_i3c_cfg::type_id::create("cfg_t");
            cfg_t.role        = ODVE_I3C_SLAVE;
            cfg_t.slv_mode    = (cc_o.target == "seq") ? ODVE_I3C_SLV_SEQ : ODVE_I3C_SLV_MEM;
            cfg_t.has_mon     = 0;
            cfg_t.vif         = vif;
            cfg_t.pid         = TGT_PID;
            cfg_t.bcr         = TGT_BCR;
            cfg_t.dcr         = TGT_DCR;
            cfg_t.static_addr = TGT_SA;
            cfg_t.nregs       = NREGS;
            uvm_config_db#(odve_i3c_cfg)::set(this, "agt_t", "cfg", cfg_t);
            agt_t = odve_i3c_agent::type_id::create("agt_t", this);
            scb_o.m_tgt = scb_o.add("tgt_agent", TGT_PID, TGT_BCR, TGT_DCR, TGT_SA);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.i3c_imp);
    endfunction
endclass : env
