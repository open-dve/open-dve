// cfg.role picks the shape: a MASTER has sequencer + master driver (drives
// txd and rts_n), a SLAVE has the slave driver (receives txd, answers on
// s_rxd, drives s_cts_n) and, in SEQ mode, the slave sequencer feeding it.
// Either gets the monitor (both lines) unless cfg.has_mon is cleared.
class odve_uart_agent extends uvm_agent;
    `uvm_component_utils(odve_uart_agent)

    odve_uart_cfg          cfg;
    odve_uart_mon          mon;
    odve_uart_sqr          sqr;       // master
    odve_uart_mst_drv_base drv;       // master
    odve_uart_slv_drv      slv_drv;   // slave
    odve_uart_slv_sqr      slv_sqr;   // slave, SEQ mode

    function new(string name = "odve_uart_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(odve_uart_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_name(), "No config object")
        if (cfg.has_mon) mon = odve_uart_mon::type_id::create("mon", this);
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_UART_MASTER) begin
            sqr = odve_uart_sqr::type_id::create("sqr", this);
            drv = odve_uart_mst_drv_base::type_id::create("drv", this);
        end else begin
            slv_drv = odve_uart_slv_drv::type_id::create("slv_drv", this);
            if (cfg.slv_mode == ODVE_UART_SLV_SEQ)
                slv_sqr = odve_uart_slv_sqr::type_id::create("slv_sqr", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) begin
            mon.vif = cfg.vif;
            mon.cfg = cfg;
        end
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_UART_MASTER) begin
            drv.vif = cfg.vif;
            drv.cfg = cfg;
            sqr.cfg = cfg;
            drv.seq_item_port.connect(sqr.seq_item_export);
        end else begin
            slv_drv.vif = cfg.vif;
            slv_drv.cfg = cfg;
            if (slv_sqr != null) begin
                slv_sqr.cfg = cfg;
                slv_drv.seq_item_port.connect(slv_sqr.seq_item_export);
                slv_drv.req_port.connect(slv_sqr.req_fifo.analysis_export);
            end
        end
    endfunction
endclass
