// Port A: transmitter agent (agt_tx) and the DUT receiver, or the receiver
// agent agt_ra (+i2s_slave=agent). Port B: the DUT transmitter and the
// receiver agent agt_rx. Clock controller of each port per cc (a_clk,
// b_clk). One monitor per bus: on port A the transmitter agent's (DUT mode)
// or the receiver agent's (agent mode), on port B the receiver agent's.
class env extends uvm_env;
    `uvm_component_utils(env)

    cc                  tc;
    odve_i2s_agent      agt_tx;   // port A transmitter
    odve_i2s_agent      agt_ra;   // port A receiver, +i2s_slave=agent
    odve_i2s_agent      agt_rx;   // port B receiver, +i2s_slave=dut
    odve_i2s_cfg        cfg_tx, cfg_ra, cfg_rx;
    odve_i2s_mon        mon_a, mon_b;
    scb                 scb_o;
    virtual dut_cfg_if  dcfg;

    function new(string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function odve_i2s_cfg make_cfg(string name, virtual odve_i2s_if vif, odve_i2s_dir_e dir, bit ctrl, bit has_mon);
        odve_i2s_cfg c = odve_i2s_cfg::type_id::create(name);
        c.vif         = vif;
        c.dir         = dir;
        c.clk_role    = ctrl ? ODVE_I2S_CLK_MASTER : ODVE_I2S_CLK_SLAVE;
        c.has_mon     = has_mon;
        c.fmt         = tc.fmt;
        c.word_len    = tc.wlen;
        c.slot_len    = tc.slen;
        c.n_slots     = tc.nslots;
        c.mono        = tc.mono;
        c.sck_half_ns = tc.sck_half_ns;
        c.src         = tc.src;
        c.gen_frames  = tc.frames;
        return c;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        virtual odve_i2s_if a_vif, b_vif;
        super.build_phase(phase);
        if (!uvm_config_db#(cc)::get(this, "", "tc", tc))
            `uvm_fatal(get_name(), "no testbench configuration 'tc' (set by base_test)")
        if (!uvm_config_db#(virtual odve_i2s_if)::get(this, "", "a_vif", a_vif))
            `uvm_fatal(get_name(), "no virtual odve_i2s_if 'a_vif' in uvm_config_db (set it from top)")
        if (!uvm_config_db#(virtual odve_i2s_if)::get(this, "", "b_vif", b_vif))
            `uvm_fatal(get_name(), "no virtual odve_i2s_if 'b_vif' in uvm_config_db (set it from top)")
        if (!uvm_config_db#(virtual dut_cfg_if)::get(this, "", "dcfg", dcfg))
            `uvm_fatal(get_name(), "no virtual dut_cfg_if 'dcfg' in uvm_config_db (set it from top)")
        `uvm_info(get_name(), tc.convert2string(), UVM_LOW)

        cfg_tx = make_cfg("cfg_tx", a_vif, ODVE_I2S_TX, tc.a_clk == "tx", tc.has_dut());
        cfg_tx.inj_kind = tc.inj;
        uvm_config_db#(odve_i2s_cfg)::set(this, "agt_tx", "cfg", cfg_tx);
        agt_tx = odve_i2s_agent::type_id::create("agt_tx", this);

        if (tc.has_dut()) begin
            cfg_rx = make_cfg("cfg_rx", b_vif, ODVE_I2S_RX, tc.b_clk == "rx", 1);
            uvm_config_db#(odve_i2s_cfg)::set(this, "agt_rx", "cfg", cfg_rx);
            agt_rx = odve_i2s_agent::type_id::create("agt_rx", this);
        end else begin
            cfg_ra = make_cfg("cfg_ra", a_vif, ODVE_I2S_RX, tc.a_clk == "rx", 1);
            uvm_config_db#(odve_i2s_cfg)::set(this, "agt_ra", "cfg", cfg_ra);
            agt_ra = odve_i2s_agent::type_id::create("agt_ra", this);
        end
        scb_o = scb::type_id::create("scb_o", this);
        scb_o.check   = tc.scb_check;
        scb_o.has_dut = tc.has_dut();

        // DUT configuration pins (static for the run)
        dcfg.fmt       = 2'(int'(tc.fmt));
        dcfg.wlen      = 6'(tc.wlen);
        dcfg.slot32    = (tc.slen == 32);
        dcfg.nslots    = 4'(tc.nslots);
        dcfg.rx_master = tc.has_dut() && tc.a_clk == "rx";
        dcfg.tx_master = tc.has_dut() && tc.b_clk == "tx";
        dcfg.half      = 8'(tc.sck_half_ns / 10);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        mon_a = tc.has_dut() ? agt_tx.mon : agt_ra.mon;
        mon_b = tc.has_dut() ? agt_rx.mon : null;
        agt_tx.drv.sent_port.connect(scb_o.sent_imp);
        mon_a.item_collected_port.connect(scb_o.a_imp);
        if (mon_b != null) mon_b.item_collected_port.connect(scb_o.b_imp);
    endfunction
endclass : env
