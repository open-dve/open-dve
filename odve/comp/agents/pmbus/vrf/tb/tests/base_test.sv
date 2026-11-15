// Builds the env; with +pmbus_slave=seq starts the device's responding
// sequence. Helpers for single PMBus commands from the host agent.
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env       env_o;
    odve_rand rng;
    bit [7:0] none[$];

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_o = env::type_id::create("env_o", this);
        rng = new(get_full_name());
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_s != null && env_o.agt_s.cfg.slv_mode == ODVE_PMBUS_SLV_SEQ) begin
            odve_pmbus_slv_seq responder = odve_pmbus_slv_seq::type_id::create("responder");
            responder.model = env_o.agt_s.cfg.model;
            fork
                responder.start(env_o.agt_s.smb.i2c.slv_sqr);
            join_none
        end
    endtask

    function odve_pmbus_item mk(odve_pmbus_op_e op, bit [7:0] cmd, bit pec = 0);
        odve_pmbus_item p = odve_pmbus_item::type_id::create("p");
        p.op   = op;
        p.cmd  = cmd;
        p.pec  = pec;
        p.addr = DEV_ADDR;
        return p;
    endfunction

    task send(odve_pmbus_item p);
        odve_pmbus_item_seq s = odve_pmbus_item_seq::type_id::create("s");
        s.item = p;
        s.start(env_o.agt.sqr);
        if (p.pec_present && !p.pec_ok && !p.bad_pec && p.force_proto == SMB_UNKNOWN)
            `uvm_error(get_name(), {"host saw a wrong PEC: ", p.convert2string()})
    endtask

    task wr(bit [7:0] cmd, bit [7:0] d[$], bit pec = 0);
        odve_pmbus_item p = mk(PMB_WRITE, cmd, pec);
        p.wdata = d;
        send(p);
    endtask

    task wr_byte(bit [7:0] cmd, bit [7:0] b, bit pec = 0);
        bit [7:0] d[$];
        d.push_back(b);
        wr(cmd, d, pec);
    endtask

    task wr_word(bit [7:0] cmd, bit [15:0] w, bit pec = 0);
        bit [7:0] d[$];
        d.push_back(w[7:0]);
        d.push_back(w[15:8]);
        wr(cmd, d, pec);
    endtask

    task send_byte(bit [7:0] cmd, bit pec = 0);
        send(mk(PMB_SEND, cmd, pec));
    endtask

    // a read: the item with its data and decoded value
    task rd(bit [7:0] cmd, output odve_pmbus_item p, input bit pec = 0);
        p = mk(PMB_READ, cmd, pec);
        send(p);
    endtask

    task rd_val(bit [7:0] cmd, output bit [15:0] v, input bit pec = 0);
        odve_pmbus_item p;
        rd(cmd, p, pec);
        v = 16'h0000;
        foreach (p.rdata[i]) if (i < 2) v[8*i +: 8] = p.rdata[i];
    endtask

    task expect_val(bit [7:0] cmd, bit [15:0] exp, input bit pec = 0);
        bit [15:0] v;
        rd_val(cmd, v, pec);
        if (v !== exp) `uvm_error(get_name(), $sformatf("%s = 0x%04h, expected 0x%04h", odve_pmbus_cmd_name(cmd), v, exp))
    endtask

    task settle();
        repeat (8) @(posedge env_o.cfg.vif.clk);
    endtask

    function bit alert_line();
        return env_o.cfg.vif.alert_n === 1'b0;
    endfunction

    task ara(bit pec = 0);
        odve_smbus_item m = odve_smbus_item::type_id::create("m");
        odve_smbus_item_seq s = odve_smbus_item_seq::type_id::create("s");
        m.proto = SMB_ARA;
        m.addr  = SMB_ARA_ADDR;
        m.pec   = pec;
        s.item  = m;
        s.start(env_o.agt.smb.sqr);
    endtask

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.agt.smb.drv.n_items != env_o.agt.mon.n_seen)
            `uvm_error(get_name(), $sformatf("host sent %0d messages, monitor decoded %0d", env_o.agt.smb.drv.n_items, env_o.agt.mon.n_seen))
    endfunction
endclass : base_test
