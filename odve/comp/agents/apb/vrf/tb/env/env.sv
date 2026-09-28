// Master agent (always) and, per +apb_slave, either the RTL slave in
// vrf/dut or the slave agent in one of its two modes on the same bus.
// The scoreboard watches the bus through the master agent's monitor; the
// slave agent gets no monitor of its own (has_mon = 0), or every transfer
// would be observed twice.
class env extends uvm_env;
    `uvm_component_utils(env)

    cc             cc_o;
    odve_apb_agent agt;       // master
    odve_apb_cfg   cfg;
    odve_apb_agent agt_s;     // slave agent, when +apb_slave=mem|seq
    odve_apb_cfg   cfg_s;
    scb            scb_o;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_apb_if vif;
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_apb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "no virtual odve_apb_if 'vif' in uvm_config_db (set it from top)")

        cfg = odve_apb_cfg::type_id::create("cfg");
        cfg.role = ODVE_APB_MASTER;
        cfg.vif  = vif;
        uvm_config_db#(odve_apb_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_apb_agent::type_id::create("agt", this);

        if (cc_o.slave_is_agent()) begin
            cfg_s = odve_apb_cfg::type_id::create("cfg_s");
            cfg_s.role     = ODVE_APB_SLAVE;
            cfg_s.slv_mode = (cc_o.slave == "seq") ? ODVE_APB_SLV_SEQ : ODVE_APB_SLV_MEM;
            cfg_s.has_mon  = 0;
            cfg_s.vif      = vif;
            uvm_config_db#(odve_apb_cfg)::set(this, "agt_s", "cfg", cfg_s);
            agt_s = odve_apb_agent::type_id::create("agt_s", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.apb_imp);
    endfunction
endclass : env
