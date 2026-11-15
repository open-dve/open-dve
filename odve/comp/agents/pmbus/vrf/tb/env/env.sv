// PMBus host agent (always) and, per +pmbus_slave, the RTL device or the
// PMBus slave agent in MEM or SEQ mode. The scoreboard gets the host
// agent's PMBus monitor.
class env extends uvm_env;
    `uvm_component_utils(env)

    cc               cc_o;
    odve_pmbus_agent agt;
    odve_pmbus_cfg   cfg;
    odve_pmbus_agent agt_s;
    odve_pmbus_cfg   cfg_s;
    scb              scb_o;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_i2c_if   ivif;
        virtual odve_smbus_if svif;
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_i2c_if)::get(this, "", "i2c_vif", ivif))
            `uvm_fatal(get_name(), "no virtual odve_i2c_if 'i2c_vif' in uvm_config_db")
        if (!uvm_config_db#(virtual odve_smbus_if)::get(this, "", "smbus_vif", svif))
            `uvm_fatal(get_name(), "no virtual odve_smbus_if 'smbus_vif' in uvm_config_db")

        cfg = odve_pmbus_cfg::type_id::create("cfg");
        cfg.role    = ODVE_PMBUS_MASTER;
        cfg.vif     = svif;
        cfg.i2c_vif = ivif;
        cfg.addr    = DEV_ADDR;
        uvm_config_db#(odve_pmbus_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_pmbus_agent::type_id::create("agt", this);

        if (cc_o.slave_is_agent()) begin
            cfg_s = odve_pmbus_cfg::type_id::create("cfg_s");
            cfg_s.role     = ODVE_PMBUS_SLAVE;
            cfg_s.slv_mode = (cc_o.slave == "seq") ? ODVE_PMBUS_SLV_SEQ : ODVE_PMBUS_SLV_MEM;
            cfg_s.has_mon  = 0;
            cfg_s.vif      = svif;
            cfg_s.i2c_vif  = ivif;
            cfg_s.addr     = DEV_ADDR;
            uvm_config_db#(odve_pmbus_cfg)::set(this, "agt_s", "cfg", cfg_s);
            agt_s = odve_pmbus_agent::type_id::create("agt_s", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.pmbus_imp);
    endfunction
endclass : env
