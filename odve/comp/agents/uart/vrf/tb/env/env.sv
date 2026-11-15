// Master agent (always: drives txd / rts_n, its monitor watches both lines)
// and, per +uart_slave, the RTL echo device or the slave agent in one of its
// two modes. The scoreboard gets every character from the master's monitor;
// with the RTL it also checks the device's error status pins.
class env extends uvm_env;
    `uvm_component_utils(env)

    cc                 cc_o;
    odve_uart_agent    agt;       // master
    odve_uart_cfg      cfg;
    odve_uart_agent    agt_s;     // slave agent, when +uart_slave=mem|seq
    odve_uart_cfg      cfg_s;
    scb                scb_o;
    virtual uart_tb_if vtb;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_uart_if vif;
        super.build_phase(phase);
        cc_o = cc::type_id::create("cc_o", this);
        if (!uvm_config_db#(virtual odve_uart_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "no virtual odve_uart_if 'vif' in uvm_config_db (set it from top)")
        if (!uvm_config_db#(virtual uart_tb_if)::get(this, "", "vtb", vtb))
            `uvm_fatal(get_name(), "no virtual uart_tb_if 'vtb' in uvm_config_db (set it from top)")

        cfg = odve_uart_cfg::type_id::create("cfg");
        cfg.role = ODVE_UART_MASTER;
        cfg.vif  = vif;
        uvm_config_db#(odve_uart_cfg)::set(this, "agt", "cfg", cfg);
        agt = odve_uart_agent::type_id::create("agt", this);

        if (cc_o.slave_is_agent()) begin
            cfg_s = odve_uart_cfg::type_id::create("cfg_s");
            cfg_s.role     = ODVE_UART_SLAVE;
            cfg_s.slv_mode = (cc_o.slave == "seq") ? ODVE_UART_SLV_SEQ : ODVE_UART_SLV_MEM;
            cfg_s.has_mon  = 0;
            cfg_s.vif      = vif;
            cfg_s.copy_format(cfg);
            uvm_config_db#(odve_uart_cfg)::set(this, "agt_s", "cfg", cfg_s);
            agt_s = odve_uart_agent::type_id::create("agt_s", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
        scb_o.cfg          = cfg;
        scb_o.vtb          = vtb;
        scb_o.check_status = !cc_o.slave_is_agent();
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.item_collected_port.connect(scb_o.uart_imp);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        apply_format();
    endfunction

    // Set the link's frame format on the master, the slave agent and the RTL
    // device. Only call it while the link is idle (base_test::wait_drain).
    function void set_format(int unsigned bits, odve_uart_parity_e par, odve_uart_stop_e stop, bit flow = 0);
        cfg.data_bits = bits;
        cfg.parity    = par;
        cfg.stop      = stop;
        cfg.flow_ctrl = flow;
        apply_format();
    endfunction

    function void apply_format();
        if (cfg_s != null) cfg_s.copy_format(cfg);
        vtb.lcr = { cfg.parity inside {ODVE_UART_PAR_MARK, ODVE_UART_PAR_SPACE},   // stick parity
                    cfg.parity inside {ODVE_UART_PAR_EVEN, ODVE_UART_PAR_SPACE},   // even select
                    cfg.parity != ODVE_UART_PAR_NONE,                              // parity enable
                    cfg.stop != ODVE_UART_STOP1,                                   // 1.5 / 2 stop bits
                    2'(cfg.data_bits - 5) };                                       // word length
        vtb.div = 16'(cfg.bit_clks / 16);
        vtb.afe = cfg.flow_ctrl;
        `uvm_info(get_name(), $sformatf("link format %s", cfg.fmt2string()), UVM_MEDIUM)
    endfunction
endclass : env
