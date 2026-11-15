// SMBus agent, layered on an i2c agent ("i2c") that carries SMBCLK/SMBDAT:
//   MASTER  smbus sequencer + odve_smbus_mst_drv, which runs each message as
//           an I2C transfer on the i2c agent (master role)
//   SLAVE   the i2c agent in slave role with an SMBus device model
//           (cfg.model, default odve_smbus_ref_model): in MEM mode inside the
//           i2c slave driver, in SEQ mode in a responding sequence the test
//           starts on i2c.slv_sqr (odve_smbus_slv_seq, model = cfg.model);
//           the agent drives SMBALERT# from model.alert
// The monitor (cfg.has_mon) decodes the i2c monitor's transfers.
class odve_smbus_agent extends uvm_agent;
    `uvm_component_utils(odve_smbus_agent)

    odve_smbus_cfg     cfg;
    odve_i2c_agent     i2c;
    odve_smbus_mon     mon;
    odve_smbus_sqr     sqr;     // master
    odve_smbus_mst_drv drv;     // master

    function new(string name = "odve_smbus_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        odve_i2c_cfg ic;
        super.build_phase(phase);
        if (!uvm_config_db#(odve_smbus_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_name(), "No config object")
        if (cfg.role == ODVE_SMBUS_SLAVE && cfg.model == null)
            cfg.model = odve_smbus_ref_model::type_id::create("model");
        if (cfg.model != null) cfg.model.addr = cfg.addr;

        ic = cfg.i2c_cfg;
        if (ic == null) begin
            ic = odve_i2c_cfg::type_id::create("i2c_cfg");
            cfg.i2c_cfg = ic;
        end
        ic.vif       = cfg.i2c_vif;
        ic.has_mon   = cfg.has_mon;
        ic.addr7     = cfg.addr;
        ic.en_addr10 = 0;
        ic.gc_en     = 0;
        if (cfg.role == ODVE_SMBUS_MASTER) begin
            ic.role = ODVE_I2C_MASTER;
            ic.t_timeout = cfg.t_timeout_min;     // the i2c monitor: a controller may ACK a last byte before a timeout
        end else begin
            ic.role = ODVE_I2C_SLAVE;
            ic.slv_mode = (cfg.slv_mode == ODVE_SMBUS_SLV_SEQ) ? ODVE_I2C_SLV_SEQ : ODVE_I2C_SLV_MEM;
            ic.t_timeout = cfg.t_timeout_dev;
            ic.model = cfg.model;
        end
        uvm_config_db#(odve_i2c_cfg)::set(this, "i2c", "cfg", ic);
        i2c = odve_i2c_agent::type_id::create("i2c", this);
        i2c.is_active = is_active;

        if (cfg.has_mon) begin
            mon = odve_smbus_mon::type_id::create("mon", this);
            mon.cfg = cfg;
        end
        if (get_is_active() == UVM_ACTIVE && cfg.role == ODVE_SMBUS_MASTER) begin
            sqr = odve_smbus_sqr::type_id::create("sqr", this);
            drv = odve_smbus_mst_drv::type_id::create("drv", this);
            drv.cfg = cfg;
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) begin
            mon.vif = cfg.vif;
            i2c.mon.item_collected_port.connect(mon.i2c_imp);
        end
        if (drv != null) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
            drv.i2c_sqr = i2c.sqr;
        end
    endfunction

    // slave: SMBALERT# follows the device model
    virtual task run_phase(uvm_phase phase);
        if (cfg.role != ODVE_SMBUS_SLAVE || get_is_active() != UVM_ACTIVE || cfg.vif == null) return;
        forever begin
            @(posedge cfg.vif.clk);
            cfg.vif.s_alert_o  <= 1'b0;
            cfg.vif.s_alert_oe <= cfg.model.alert;
        end
    endtask
endclass
