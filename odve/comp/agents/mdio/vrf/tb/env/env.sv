// Master agent (STA, always) and, per +mdio_slave, the RTL PHY, the slave
// agent in one of its two modes, or both on the same bus. The scoreboard
// watches the bus through the master agent's monitor; the slave agent gets
// no monitor of its own (has_mon = 0).
class env extends uvm_env;
    `uvm_component_utils(env)

    cc              cc_o;
    odve_mdio_agent agt;       // master (STA)
    odve_mdio_cfg   cfg;
    odve_mdio_agent agt_s;     // slave agent (PHY model), when +mdio_slave=mem|seq|multi
    odve_mdio_cfg   cfg_s;
    scb             scb_o;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_mdio_if vif;
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_mdio_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "no virtual odve_mdio_if 'vif' in uvm_config_db (set it from top)")

        cfg = odve_mdio_cfg::type_id::create("cfg");
        cfg.role = ODVE_MDIO_MASTER;
        cfg.vif  = vif;
        uvm_config_db#(odve_mdio_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_mdio_agent::type_id::create("agt", this);

        if (cc_o.has_slave_agent()) begin
            cfg_s = odve_mdio_cfg::type_id::create("cfg_s");
            cfg_s.role     = ODVE_MDIO_SLAVE;
            cfg_s.slv_mode = (cc_o.slave == "seq") ? ODVE_MDIO_SLV_SEQ : ODVE_MDIO_SLV_MEM;
            cfg_s.has_mon  = 0;
            cfg_s.vif      = vif;
            cfg_s.phyads   = cc_o.agent_addrs;
            cfg_s.prtads   = cc_o.agent_addrs;
            uvm_config_db#(odve_mdio_cfg)::set(this, "agt_s", "cfg", cfg_s);
            agt_s = odve_mdio_agent::type_id::create("agt_s", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        scb_o.model.phyads  = cc_o.addrs;
        scb_o.model.prtads  = cc_o.addrs;
        scb_o.model.pre_min = cfg.pre_min;
        agt.mon.item_collected_port.connect(scb_o.mdio_imp);
    endfunction
endclass : env
