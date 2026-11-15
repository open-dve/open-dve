// Builds the env; with +smbus_slave=seq starts the device's responding
// sequence. Helpers to send single SMBus messages from the host agent.
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
        if (env_o.agt_s != null && env_o.agt_s.cfg.slv_mode == ODVE_SMBUS_SLV_SEQ) begin
            odve_smbus_slv_seq responder = odve_smbus_slv_seq::type_id::create("responder");
            responder.model = env_o.agt_s.cfg.model;
            fork
                responder.start(env_o.agt_s.i2c.slv_sqr);
            join_none
        end
    endtask

    function odve_smbus_item mk(odve_smbus_proto_e p, bit [7:0] cmd = 8'h00, bit pec = 0, bit [6:0] addr = DEV_ADDR);
        odve_smbus_item m = odve_smbus_item::type_id::create("m");
        m.proto = p;
        m.cmd   = cmd;
        m.pec   = pec;
        m.addr  = addr;
        return m;
    endfunction

    task send(odve_smbus_item m);
        odve_smbus_item_seq s = odve_smbus_item_seq::type_id::create("s");
        s.item = m;
        s.start(env_o.agt.sqr);
        if (m.pec_present && !m.pec_ok && !m.bad_pec)
            `uvm_error(get_name(), {"host saw a wrong PEC: ", m.convert2string()})
    endtask

    task msg(odve_smbus_proto_e p, bit [7:0] cmd = 8'h00, bit [7:0] w[$] = none, bit pec = 0);
        odve_smbus_item m = mk(p, cmd, pec);
        m.wdata = w;
        send(m);
    endtask

    function void rand_bytes(ref bit [7:0] q[$], input int unsigned n);
        q.delete();
        repeat (n) q.push_back(8'(rng.u16()));
    endfunction

    // the device's STATUS (Receive Byte), as the host read it
    task get_status(output bit [7:0] st);
        odve_smbus_item m = mk(SMB_RECV_BYTE, 8'h00, 1);
        send(m);
        st = (m.rdata.size() > 0) ? m.rdata[0] : 8'h00;
    endtask

    // SMBALERT#, once the device has had a few cycles after the last STOP
    task settle();
        repeat (8) @(posedge env_o.cfg.vif.clk);
    endtask

    function bit alert_line();
        return env_o.cfg.vif.alert_n === 1'b0;
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.agt.drv.n_items != env_o.agt.mon.n_seen)
            `uvm_error(get_name(), $sformatf("host sent %0d messages, monitor decoded %0d", env_o.agt.drv.n_items, env_o.agt.mon.n_seen))
    endfunction
endclass : base_test
