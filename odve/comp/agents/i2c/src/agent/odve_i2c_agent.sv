// cfg.role picks the shape: a MASTER has sequencer + controller driver, a
// SLAVE has the target driver and, in SEQ mode, the slave sequencer feeding
// it. Either gets the monitor unless cfg.has_mon is cleared (one bus, one
// monitor).
class odve_i2c_agent extends uvm_agent;
    `uvm_component_utils(odve_i2c_agent)

    odve_i2c_cfg          cfg;
    odve_i2c_mon          mon;
    odve_i2c_sqr          sqr;       // master
    odve_i2c_mst_drv_base drv;       // master
    odve_i2c_slv_drv      slv_drv;   // slave
    odve_i2c_slv_sqr      slv_sqr;   // slave, SEQ mode

    function new(string name = "odve_i2c_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(odve_i2c_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_name(), "No config object")
        if (cfg.has_mon) begin
            mon = odve_i2c_mon::type_id::create("mon", this);
            mon.cfg = cfg;
        end
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_I2C_MASTER) begin
            sqr = odve_i2c_sqr::type_id::create("sqr", this);
            drv = odve_i2c_mst_drv_base::type_id::create("drv", this);
            drv.cfg = cfg;
        end else begin
            slv_drv = odve_i2c_slv_drv::type_id::create("slv_drv", this);
            slv_drv.cfg = cfg;
            if (cfg.slv_mode == ODVE_I2C_SLV_SEQ)
                slv_sqr = odve_i2c_slv_sqr::type_id::create("slv_sqr", this);
            else if (cfg.model == null)
                cfg.model = odve_i2c_mem_model::type_id::create("model");
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) mon.vif = cfg.vif;
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_I2C_MASTER) begin
            drv.vif = cfg.vif;
            drv.seq_item_port.connect(sqr.seq_item_export);
        end else begin
            slv_drv.vif = cfg.vif;
            if (slv_sqr != null) begin
                slv_drv.seq_item_port.connect(slv_sqr.seq_item_export);
                slv_drv.req_port.connect(slv_sqr.req_fifo.analysis_export);
            end
        end
    endfunction
endclass
