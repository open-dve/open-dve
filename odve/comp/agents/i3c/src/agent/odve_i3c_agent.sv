// cfg.role picks the shape: a MASTER (controller) has sequencer + controller
// driver, a SLAVE (target) has the target driver and, in SEQ mode, the
// target sequencer feeding it. Either gets the monitor unless cfg.has_mon is
// cleared (one bus, one monitor).
class odve_i3c_agent extends uvm_agent;
    `uvm_component_utils(odve_i3c_agent)

    odve_i3c_cfg          cfg;
    odve_i3c_mon          mon;
    odve_i3c_sqr          sqr;       // controller
    odve_i3c_mst_drv_base drv;       // controller
    odve_i3c_slv_drv      slv_drv;   // target
    odve_i3c_slv_sqr      slv_sqr;   // target, SEQ mode

    function new(string name = "odve_i3c_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(odve_i3c_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_name(), "No config object")
        end
        if (cfg.has_mon) mon = odve_i3c_mon::type_id::create("mon", this);
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_I3C_MASTER) begin
            sqr = odve_i3c_sqr::type_id::create("sqr", this);
            drv = odve_i3c_mst_drv_base::type_id::create("drv", this);
        end else begin
            slv_drv = odve_i3c_slv_drv::type_id::create("slv_drv", this);
            if (cfg.slv_mode == ODVE_I3C_SLV_SEQ)
                slv_sqr = odve_i3c_slv_sqr::type_id::create("slv_sqr", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) begin
            mon.vif = cfg.vif;
            mon.cfg = cfg;
        end
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_I3C_MASTER) begin
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
