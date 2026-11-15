// Master agent (always) with the monitor, and per +spi_slave either the two
// RTL slaves in top or two slave agents (one per chip select, no monitor of
// their own) on the same bus. Every agent cfg shares the same per-chip-select
// format objects (cfg.dev[]), and set_format() changes a slave's format for
// the agents and the RTL straps at once - between frames only.
class env extends uvm_env;
    `uvm_component_utils(env)

    cc             cc_o;
    odve_spi_agent agt;          // master
    odve_spi_cfg   cfg;
    odve_spi_agent agt_s[2];     // slave agents, when +spi_slave=mem|seq
    odve_spi_cfg   cfg_s[2];
    scb            scb_o;
    virtual spi_strap_if strap;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_spi_if vif;
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_spi_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "no virtual odve_spi_if 'vif' in uvm_config_db (set it from top)")
        if (!uvm_config_db#(virtual spi_strap_if)::get(this, "", "strap", strap))
            `uvm_fatal(get_name(), "no virtual spi_strap_if 'strap' in uvm_config_db (set it from top)")

        cfg = odve_spi_cfg::type_id::create("cfg");
        cfg.role = ODVE_SPI_MASTER;
        cfg.vif  = vif;
        cfg.ncs  = 2;
        // two slaves of different formats from the start
        cfg.dev[1].cpol = 1; cfg.dev[1].cpha = 1; cfg.dev[1].lsb_first = 1; cfg.dev[1].word_bits = 16;
        uvm_config_db#(odve_spi_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_spi_agent::type_id::create("agt", this);

        if (cc_o.slave_is_agent()) begin
            foreach (agt_s[i]) begin
                string nm = $sformatf("agt_s%0d", i);
                cfg_s[i] = odve_spi_cfg::type_id::create($sformatf("cfg_s%0d", i));
                cfg_s[i].role     = ODVE_SPI_SLAVE;
                cfg_s[i].slv_mode = (cc_o.slave == "seq") ? ODVE_SPI_SLV_SEQ : ODVE_SPI_SLV_MEM;
                cfg_s[i].has_mon  = 0;
                cfg_s[i].vif      = vif;
                cfg_s[i].ncs      = cfg.ncs;
                cfg_s[i].dev      = cfg.dev;          // the same format objects
                cfg_s[i].slv_cs   = i;
                cfg_s[i].slv_id   = (i == 0) ? 8'hA5 : 8'h3C;
                uvm_config_db#(odve_spi_cfg)::set(this, nm, "cfg", cfg_s[i]);
                agt_s[i] = odve_spi_agent::type_id::create(nm, this);
            end
        end
        scb_o = scb::type_id::create("scb_o", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.spi_imp);
    endfunction

    function void drive_straps();
        for (int i = 0; i < 2; i++) begin
            strap.cpol[i]      = cfg.dev[i].cpol;
            strap.cpha[i]      = cfg.dev[i].cpha;
            strap.lsb_first[i] = cfg.dev[i].lsb_first;
            strap.wsel[i]      = (cfg.dev[i].word_bits == 8) ? 2'd0 : (cfg.dev[i].word_bits == 16) ? 2'd1 : 2'd2;
        end
    endfunction

    virtual function void start_of_simulation_phase(uvm_phase phase);
        drive_straps();
    endfunction

    // Change the format of chip select cs (agents + RTL straps); call between frames.
    function void set_format(int unsigned cs, bit cpol, bit cpha, bit lsb_first, int unsigned word_bits);
        cfg.dev[cs].cpol      = cpol;
        cfg.dev[cs].cpha      = cpha;
        cfg.dev[cs].lsb_first = lsb_first;
        cfg.dev[cs].word_bits = word_bits;
        drive_straps();
    endfunction
endclass : env
