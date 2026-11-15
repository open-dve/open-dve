// Master agent (always, with the monitor) and, per +qspi_slave, either the
// RTL flash in top or the slave agent (behavioural flash, no monitor of its
// own) on the same bus. All cfgs share one odve_qspi_bus_cfg (mode, QPI).
// The slave agent gets the RTL flash's sizes and timing.
class env extends uvm_env;
    `uvm_component_utils(env)

    cc              cc_o;
    odve_qspi_agent agt;       // master
    odve_qspi_cfg   cfg;
    odve_qspi_agent agt_s;     // flash, when +qspi_slave=mem|seq
    odve_qspi_cfg   cfg_s;
    scb             scb_o;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_qspi_if vif;
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_qspi_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "no virtual odve_qspi_if 'vif' in uvm_config_db (set it from top)")

        cfg = odve_qspi_cfg::type_id::create("cfg");
        cfg.role = ODVE_QSPI_MASTER;
        cfg.vif  = vif;
        cfg.bus.cpol = (cc_o.mode == 3);
        uvm_config_db#(odve_qspi_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_qspi_agent::type_id::create("agt", this);

        if (cc_o.slave_is_agent()) begin
            cfg_s = odve_qspi_cfg::type_id::create("cfg_s");
            cfg_s.role     = ODVE_QSPI_SLAVE;
            cfg_s.slv_mode = (cc_o.slave == "seq") ? ODVE_QSPI_SLV_SEQ : ODVE_QSPI_SLV_MEM;
            cfg_s.has_mon  = 0;
            cfg_s.vif      = vif;
            cfg_s.bus      = cfg.bus;           // one bus format for everybody
            uvm_config_db#(odve_qspi_cfg)::set(this, "agt_s", "cfg", cfg_s);
            agt_s = odve_qspi_agent::type_id::create("agt_s", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
        scb_o.cfg = cfg;
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.qspi_imp);
    endfunction
endclass : env
