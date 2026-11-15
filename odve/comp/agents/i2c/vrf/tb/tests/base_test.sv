// Builds the env; with +i2c_slave=seq starts the responding sequence of the
// slave agent. Helpers for directed transfers on the master agent.
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env       env_o;
    bit [7:0] none[$];      // an empty byte list
    odve_rand rng;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_o = env::type_id::create("env_o", this);
        rng = new(get_full_name());
    endfunction : build_phase

    // The reactive slave needs its responder: started in the background, it
    // never ends and holds no objection.
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_s != null && env_o.agt_s.slv_sqr != null) begin
            odve_i2c_slv_model_seq responder = odve_i2c_slv_model_seq::type_id::create("responder");
            fork
                responder.start(env_o.agt_s.slv_sqr);
            join_none
        end
    endtask

    // One transfer on the master agent; the item comes back with the results.
    task xfer(odve_i2c_item it);
        odve_i2c_item_seq s = odve_i2c_item_seq::type_id::create("s");
        s.item = it;
        s.start(env_o.agt.sqr);
    endtask

    function odve_i2c_item mk(odve_i2c_kind_e kind, bit [9:0] addr, bit addr10 = 0);
        odve_i2c_item it = odve_i2c_item::type_id::create("it");
        it.kind   = kind;
        it.addr   = addr;
        it.addr10 = addr10;
        return it;
    endfunction

    function bit [9:0] tgt(bit a10);
        return a10 ? TGT_ADDR10 : 10'(TGT_ADDR7);
    endfunction

    // write `data` from register `ptr`
    task wr_regs(int unsigned ptr, bit [7:0] data[$], bit a10 = 0);
        odve_i2c_item it = mk(I2C_WRITE, tgt(a10), a10);
        it.wdata.push_back(8'(ptr));
        foreach (data[i]) it.wdata.push_back(data[i]);
        xfer(it);
    endtask

    // combined format: pointer, Sr, read n
    task rd_regs(int unsigned ptr, int unsigned n, bit a10 = 0);
        odve_i2c_item it = mk(I2C_WRITE_READ, tgt(a10), a10);
        it.wdata.push_back(8'(ptr));
        it.nrd = n;
        xfer(it);
    endtask

    // current-address read
    task rd_cur(int unsigned n, bit a10 = 0);
        odve_i2c_item it = mk(I2C_READ, tgt(a10), a10);
        it.nrd = n;
        xfer(it);
    endtask

    function void rand_bytes(ref bit [7:0] q[$], input int unsigned n);
        q.delete();
        repeat (n) q.push_back(8'(rng.u16()));
    endfunction

    // the scoreboard must have seen exactly what the master ran
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.agt.drv.n_items != env_o.agt.mon.n_seen)
            `uvm_error(get_name(), $sformatf("master ran %0d transfers, monitor reported %0d", env_o.agt.drv.n_items, env_o.agt.mon.n_seen))
    endfunction
endclass : base_test
