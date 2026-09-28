class env extends uvm_env;
    `uvm_component_utils(env)

    odve_apb_agent agt;
    odve_apb_cfg   cfg;
    cc             cc_o;
    scb            scb_o;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg = odve_apb_cfg::type_id::create("cfg");
        if (!uvm_config_db#(virtual odve_apb_if)::get(this, "", "vif", cfg.vif))
            `uvm_fatal(get_name(), "no virtual odve_apb_if 'vif' in uvm_config_db (set it from top)")
        uvm_config_db#(odve_apb_cfg)::set(this, "agt", "cfg", cfg);
        agt   = odve_apb_agent::type_id::create("agt", this);
        cc_o  = cc::type_id::create("cc_o", this);
        scb_o = scb::type_id::create("scb_o", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.apb_imp);
    endfunction
endclass : env
