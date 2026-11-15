// cfg.role picks the shape: a MASTER has sequencer + master driver, a SLAVE
// has the slave driver (answering cfg.slv_cs) and, in SEQ mode, the slave
// sequencer feeding it. Either gets the monitor unless cfg.has_mon is
// cleared (one bus, one monitor).
class odve_spi_agent extends uvm_agent;
    `uvm_component_utils(odve_spi_agent)

    odve_spi_cfg          cfg;
    odve_spi_mon          mon;
    odve_spi_sqr          sqr;       // master
    odve_spi_mst_drv_base drv;       // master
    odve_spi_slv_drv      slv_drv;   // slave
    odve_spi_slv_sqr      slv_sqr;   // slave, SEQ mode

    function new(string name = "odve_spi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(odve_spi_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_name(), "No config object")
        if (cfg.ncs == 0 || cfg.ncs > `ODVE_SPI_MAX_CS)
            `uvm_fatal(get_name(), $sformatf("cfg.ncs=%0d, expected 1..%0d", cfg.ncs, `ODVE_SPI_MAX_CS))
        if (cfg.has_mon) begin
            mon = odve_spi_mon::type_id::create("mon", this);
            mon.cfg = cfg;
        end
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_SPI_MASTER) begin
            sqr = odve_spi_sqr::type_id::create("sqr", this);
            drv = odve_spi_mst_drv_base::type_id::create("drv", this);
            sqr.cfg = cfg;
            drv.cfg = cfg;
        end else begin
            slv_drv = odve_spi_slv_drv::type_id::create("slv_drv", this);
            slv_drv.cfg = cfg;
            if (cfg.slv_mode == ODVE_SPI_SLV_SEQ) begin
                slv_sqr = odve_spi_slv_sqr::type_id::create("slv_sqr", this);
                slv_sqr.cfg = cfg;
            end
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) mon.vif = cfg.vif;
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.role == ODVE_SPI_MASTER) begin
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
