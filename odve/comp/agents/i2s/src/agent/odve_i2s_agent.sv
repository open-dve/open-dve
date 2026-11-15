// One agent per device on a bus. cfg.dir (TX/RX) and cfg.clk_role (clock
// controller / target) pick the shape: a clock controller gets the master
// driver (SCK/WS generation, SD if transmitter), a target the slave driver
// (follows SCK/WS, SD if transmitter). A transmitter fed by sequences
// (cfg.src == SRC_SEQ) has a sequencer. The monitor is there unless
// cfg.has_mon is cleared (one bus, one monitor).
class odve_i2s_agent extends uvm_agent;
    `uvm_component_utils(odve_i2s_agent)

    odve_i2s_cfg      cfg;
    odve_i2s_mon      mon;
    odve_i2s_sqr      sqr;
    odve_i2s_drv_base drv;

    function new(string name = "odve_i2s_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        string err;
        super.build_phase(phase);
        if (!uvm_config_db#(odve_i2s_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_name(), "No config object")
        err = cfg.check();
        if (err != "")
            `uvm_fatal(get_name(), $sformatf("bad configuration (%s): %s", cfg.convert2string(), err))
        if (cfg.has_mon) begin
            mon = odve_i2s_mon::type_id::create("mon", this);
            mon.cfg = cfg;
        end
        if (get_is_active() != UVM_ACTIVE) return;
        if (cfg.clk_role == ODVE_I2S_CLK_MASTER) drv = odve_i2s_mst_drv::type_id::create("drv", this);
        else                                     drv = odve_i2s_slv_drv::type_id::create("drv", this);
        drv.cfg = cfg;
        if (cfg.dir == ODVE_I2S_TX && cfg.src == ODVE_I2S_SRC_SEQ) begin
            sqr = odve_i2s_sqr::type_id::create("sqr", this);
            sqr.cfg = cfg;
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (mon != null) mon.vif = cfg.vif;
        if (drv != null) drv.vif = cfg.vif;
        if (sqr != null) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
