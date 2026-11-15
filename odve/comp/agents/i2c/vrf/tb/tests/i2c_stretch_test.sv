// Clock stretching by the target (UM10204 3.1.9): CTRL (register 15) set to
// hold SCL low after every acknowledge; the controller must wait, and the
// traffic must still check out. The monitor must have seen stretching.
// REQ-I2C-011.
class i2c_stretch_test extends base_test;
    `uvm_component_utils(i2c_stretch_test)

    function new(string name = "i2c_stretch_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_i2c_rand_seq s = odve_i2c_rand_seq::type_id::create("s");
        bit [7:0] d[$];
        int unsigned n_before;
        super.run_phase(phase);
        phase.raise_objection(this);
        wr_regs(15, '{8'd25});
        s.rng       = rng.spawn("rand_seq");
        s.n         = 20;
        s.nregs     = 15;          // pointers 0..14: CTRL stays as set (unless a long write wraps into it)
        s.max_wr    = 6;
        s.max_rd    = 6;
        s.p_addr10  = 30;
        s.start(env_o.agt.sqr);
        wr_regs(15, '{8'd3});
        rd_regs(15, 1);
        wr_regs(15, '{8'd0});
        n_before = env_o.agt.mon.n_stretched;
        rd_regs(0, 4);
        if (env_o.agt.mon.n_stretched != n_before)
            `uvm_error(get_name(), "stretching seen with CTRL = 0")
        if (n_before == 0)
            `uvm_error(get_name(), "the monitor saw no clock stretching")
        else
            `uvm_info(get_name(), $sformatf("%0d stretched transfers", n_before), UVM_LOW)
        phase.drop_objection(this);
    endtask : run_phase
endclass : i2c_stretch_test
