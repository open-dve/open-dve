// Master agent (always), the slave agent when +rffe_slave=mem|seq, and the
// scoreboard on the master agent's monitor. The slave agent has no monitor
// of its own (has_mon = 0): one bus, one observer.
class env extends uvm_env;
    `uvm_component_utils(env)

    cc              cc_o;
    odve_rffe_agent agt;       // master
    odve_rffe_cfg   cfg;
    odve_rffe_agent agt_s;     // primary slave, when +rffe_slave=mem|seq
    odve_rffe_cfg   cfg_s;
    scb             scb_o;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_rffe_if vif;
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_rffe_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "no virtual odve_rffe_if 'vif' in uvm_config_db (set it from top)")

        cfg = odve_rffe_cfg::type_id::create("cfg");
        cfg.role = ODVE_RFFE_MASTER;
        cfg.vif  = vif;
        uvm_config_db#(odve_rffe_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_rffe_agent::type_id::create("agt", this);

        if (cc_o.slave_is_agent()) begin
            cfg_s = odve_rffe_cfg::type_id::create("cfg_s");
            cfg_s.role     = ODVE_RFFE_SLAVE;
            cfg_s.slv_mode = (cc_o.slave == "seq") ? ODVE_RFFE_SLV_SEQ : ODVE_RFFE_SLV_MEM;
            cfg_s.has_mon  = 0;
            cfg_s.usid     = cc_o.usid_prim;
            cfg_s.nregs    = cc_o.nregs;
            cfg_s.vif      = vif;
            uvm_config_db#(odve_rffe_cfg)::set(this, "agt_s", "cfg", cfg_s);
            agt_s = odve_rffe_agent::type_id::create("agt_s", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
        scb_o.usids = '{cc_o.usid_prim, cc_o.usid_sec};
        scb_o.nregs = cc_o.nregs;
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.rffe_imp);
    endfunction
endclass : env
