// cfg.role picks the shape: a MASTER (JTAG host) has sequencer + master
// driver, a SLAVE (behavioural TAP) has the slave driver and, in SEQ mode,
// the slave sequencer feeding it. Either gets the monitor unless
// cfg.has_mon is cleared (one bus, one monitor).
class odve_jtag_agent extends uvm_agent;
    `uvm_component_utils(odve_jtag_agent)

    odve_jtag_cfg          cfg;
    odve_jtag_mon          mon;
    odve_jtag_sqr          sqr;       // master
    odve_jtag_mst_drv_base drv;       // master
    odve_jtag_slv_drv      slv_drv;   // slave
    odve_jtag_slv_sqr      slv_sqr;   // slave, SEQ mode

    function new(string name = "odve_jtag_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(odve_jtag_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_name(), "No config object")
        end
        if (cfg.has_mon) mon = odve_jtag_mon::type_id::create("mon", this);
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_JTAG_MASTER) begin
            sqr = odve_jtag_sqr::type_id::create("sqr", this);
            drv = odve_jtag_mst_drv_base::type_id::create("drv", this);
        end else begin
            slv_drv = odve_jtag_slv_drv::type_id::create("slv_drv", this);
            if (cfg.slv_mode == ODVE_JTAG_SLV_SEQ)
                slv_sqr = odve_jtag_slv_sqr::type_id::create("slv_sqr", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) begin
            mon.vif = cfg.vif;
            mon.cfg = cfg;
        end
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_JTAG_MASTER) begin
            drv.vif = cfg.vif;
            drv.cfg = cfg;
            drv.seq_item_port.connect(sqr.seq_item_export);
        end else begin
            slv_drv.vif = cfg.vif;
            slv_drv.cfg = cfg;
            if (slv_sqr != null) begin
                slv_drv.seq_item_port.connect(slv_sqr.seq_item_export);
                slv_drv.req_port.connect(slv_sqr.req_fifo.analysis_export);
            end
        end
    endfunction
endclass
