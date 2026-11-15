// PMBus agent, layered on an smbus agent ("smb", itself on an i2c agent):
//   MASTER  pmbus sequencer + odve_pmbus_mst_drv, which runs each command as
//           an SMBus message on the smbus agent (master role)
//   SLAVE   the smbus agent in slave role with a PMBus device model
//           (cfg.model, default odve_pmbus_dev_model): MEM mode inside the
//           i2c slave driver, SEQ mode in a responding sequence the test
//           starts on smb.i2c.slv_sqr (odve_smbus_slv_seq, model = cfg.model)
// The monitor (cfg.has_mon) decodes the smbus monitor's messages.
class odve_pmbus_agent extends uvm_agent;
    `uvm_component_utils(odve_pmbus_agent)

    odve_pmbus_cfg     cfg;
    odve_smbus_agent   smb;
    odve_pmbus_mon     mon;
    odve_pmbus_sqr     sqr;
    odve_pmbus_mst_drv drv;

    function new(string name = "odve_pmbus_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        odve_smbus_cfg sc;
        super.build_phase(phase);
        if (!uvm_config_db#(odve_pmbus_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_name(), "No config object")
        if (cfg.role == ODVE_PMBUS_SLAVE && cfg.model == null)
            cfg.model = odve_pmbus_dev_model::type_id::create("model");
        if (cfg.model != null) cfg.model.npages = cfg.npages;

        sc = cfg.smb_cfg;
        if (sc == null) begin
            sc = odve_smbus_cfg::type_id::create("smb_cfg");
            cfg.smb_cfg = sc;
        end
        sc.vif      = cfg.vif;
        sc.i2c_vif  = cfg.i2c_vif;
        sc.has_mon  = cfg.has_mon;
        sc.addr     = cfg.addr;
        sc.role     = (cfg.role == ODVE_PMBUS_MASTER) ? ODVE_SMBUS_MASTER : ODVE_SMBUS_SLAVE;
        sc.slv_mode = (cfg.slv_mode == ODVE_PMBUS_SLV_SEQ) ? ODVE_SMBUS_SLV_SEQ : ODVE_SMBUS_SLV_MEM;
        sc.model    = cfg.model;
        for (int c = 0; c < 256; c++) sc.cmd_tab[c] = odve_pmbus_cmd_kind(8'(c));
        uvm_config_db#(odve_smbus_cfg)::set(this, "smb", "cfg", sc);
        smb = odve_smbus_agent::type_id::create("smb", this);
        smb.is_active = is_active;

        if (cfg.has_mon) begin
            mon = odve_pmbus_mon::type_id::create("mon", this);
            mon.cfg = cfg;
        end
        if (get_is_active() == UVM_ACTIVE && cfg.role == ODVE_PMBUS_MASTER) begin
            sqr = odve_pmbus_sqr::type_id::create("sqr", this);
            drv = odve_pmbus_mst_drv::type_id::create("drv", this);
            drv.cfg = cfg;
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) smb.mon.item_collected_port.connect(mon.smb_imp);
        if (drv != null) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
            drv.smb_sqr = smb.sqr;
        end
    endfunction
endclass
