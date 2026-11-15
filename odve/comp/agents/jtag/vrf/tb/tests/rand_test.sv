// Random mix (odve_jtag_rand_seq): resets through TMS and TRST_n, IR scans
// with known and unassigned instructions, DR scans of 0..80 bits, pauses,
// idle cycles and detours to random states; the scoreboard checks every bit.
class rand_test extends base_test;
    `uvm_component_utils(rand_test)

    function new(string name = "rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_jtag_rand_seq s = odve_jtag_rand_seq::type_id::create("rnd");
        super.run_phase(phase);
        phase.raise_objection(this);
        s.n      = 120;
        s.n_taps = n_taps;
        s.rng    = rng.spawn("rnd");
        s.start(env_o.agt.sqr);
        phase.drop_objection(this);
    endtask : run_phase
endclass : rand_test
