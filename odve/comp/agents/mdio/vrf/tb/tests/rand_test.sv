// Random mixed traffic over both clauses and every responding address,
// 15% to addresses/MMDs nobody answers, 0..2 idle cycles between frames,
// some preambles longer than 32 - all checked by the scoreboard.
class rand_test extends base_test;
    `uvm_component_utils(rand_test)

    function new(string name = "rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_mdio_rand_seq rs = odve_mdio_rand_seq::type_id::create("rs");
        super.run_phase(phase);
        `uvm_info(get_name(), $sformatf("odve_rand: SEED %0d", odve_rand::run_seed()), UVM_NONE)
        phase.raise_objection(this);
        rs.n            = 150;
        rs.addrs        = env_o.cc_o.addrs;
        rs.miss_pct     = 15;
        rs.max_idle     = 2;
        rs.long_pre_pct = 20;
        run_seq(rs);
        phase.drop_objection(this);
    endtask : run_phase
endclass : rand_test
