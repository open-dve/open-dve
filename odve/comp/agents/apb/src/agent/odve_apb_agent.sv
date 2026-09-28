// cfg.role picks the shape: a MASTER has sequencer + master driver, a SLAVE
// has the slave driver and, in SEQ mode, the slave sequencer feeding it.
// Either gets the monitor unless cfg.has_mon is cleared (one bus, one monitor).
class odve_apb_agent extends uvm_agent;
    `uvm_component_utils(odve_apb_agent)

    odve_apb_cfg          cfg;
    odve_apb_mon          mon;
    odve_apb_sqr          sqr;       // master
    odve_apb_mst_drv_base drv;       // master
    odve_apb_slv_drv      slv_drv;   // slave
    odve_apb_slv_sqr      slv_sqr;   // slave, SEQ mode

    function new(string name = "odve_apb_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(odve_apb_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_name(), "No config object")
        end
        if (cfg.has_mon) mon = odve_apb_mon::type_id::create("mon", this);
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_APB_MASTER) begin
            sqr = odve_apb_sqr::type_id::create("sqr", this);
            drv = odve_apb_mst_drv_base::type_id::create("drv", this);
        end else begin
            slv_drv = odve_apb_slv_drv::type_id::create("slv_drv", this);
            slv_drv.cfg = cfg;
            if (cfg.slv_mode == ODVE_APB_SLV_SEQ)
                slv_sqr = odve_apb_slv_sqr::type_id::create("slv_sqr", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) mon.vif = cfg.vif;
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_APB_MASTER) begin
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
