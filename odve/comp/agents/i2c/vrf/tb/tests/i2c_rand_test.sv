// Random register traffic back to back: every transfer kind, 7- and 10-bit,
// lengths 0..20 (pointer wrap), a few absent addresses and bad pointers.
// Writes to register 15 (CTRL) turn the target's clock stretching on and
// off on the way. REQ-I2C-001..010, 012.
class i2c_rand_test extends base_test;
    `uvm_component_utils(i2c_rand_test)

    function new(string name = "i2c_rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_i2c_rand_seq s = odve_i2c_rand_seq::type_id::create("s");
        super.run_phase(phase);
        phase.raise_objection(this);
        s.rng        = rng.spawn("rand_seq");
        s.n          = 60;
        s.tgt_addr7  = TGT_ADDR7;
        s.tgt_addr10 = TGT_ADDR10;
        s.p_addr10   = 30;
        s.p_bad_addr = 5;
        s.p_bad_ptr  = 5;
        s.max_wr     = 20;
        s.max_rd     = 20;
        s.start(env_o.agt.sqr);
        phase.drop_objection(this);
    endtask : run_phase
endclass : i2c_rand_test
