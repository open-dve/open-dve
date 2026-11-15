// SMBus host agent (always) and, per +smbus_slave, the RTL device or the
// SMBus slave agent in MEM or SEQ mode on the same bus. The scoreboard
// gets the host agent's monitor (the slave agent has none).
class env extends uvm_env;
    `uvm_component_utils(env)

    cc               cc_o;
    odve_smbus_agent agt;       // host
    odve_smbus_cfg   cfg;
    odve_smbus_agent agt_s;     // device, +smbus_slave=mem|seq
    odve_smbus_cfg   cfg_s;
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

        cfg = odve_smbus_cfg::type_id::create("cfg");
        cfg.role    = ODVE_SMBUS_MASTER;
        cfg.vif     = svif;
        cfg.i2c_vif = ivif;
        cfg.set_ref_cmds();
        uvm_config_db#(odve_smbus_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_smbus_agent::type_id::create("agt", this);

        if (cc_o.slave_is_agent()) begin
            cfg_s = odve_smbus_cfg::type_id::create("cfg_s");
            cfg_s.role     = ODVE_SMBUS_SLAVE;
            cfg_s.slv_mode = (cc_o.slave == "seq") ? ODVE_SMBUS_SLV_SEQ : ODVE_SMBUS_SLV_MEM;
            cfg_s.has_mon  = 0;
            cfg_s.vif      = svif;
            cfg_s.i2c_vif  = ivif;
            cfg_s.addr     = DEV_ADDR;
            cfg_s.t_timeout_dev = DEV_TMO;
            cfg_s.set_ref_cmds();
            uvm_config_db#(odve_smbus_cfg)::set(this, "agt_s", "cfg", cfg_s);
            agt_s = odve_smbus_agent::type_id::create("agt_s", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
        scb_o.cfg = cfg;
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.smbus_imp);
    endfunction
endclass : env
