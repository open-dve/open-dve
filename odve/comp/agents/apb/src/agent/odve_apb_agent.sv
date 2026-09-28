class odve_apb_agent extends uvm_agent;
    `uvm_component_utils(odve_apb_agent)

    odve_apb_cfg          cfg;
    odve_apb_sqr          sqr;
    odve_apb_mon          mon;
    odve_apb_mst_drv_base drv;

    function new(string name = "odve_apb_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(odve_apb_cfg)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal(get_name(), "No config object")
        end
        mon = odve_apb_mon::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = odve_apb_sqr::type_id::create("sqr", this);
            drv = odve_apb_mst_drv_base::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        mon.vif = cfg.vif;
        if (get_is_active() == UVM_ACTIVE) begin
            drv.vif = cfg.vif;
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction
endclass
