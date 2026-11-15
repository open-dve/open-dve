// Builds the env; starts the responding sequence when the primary slave is
// the reactive slave agent (+rffe_slave=seq); helpers for the scenario
// tests. Runs no traffic of its own.
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env       env_o;
    odve_rand rng;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_o = env::type_id::create("env_o", this);
        rng   = new(get_full_name());
    endfunction : build_phase

    // The responder never ends and holds no objection: the test decides when the run is over.
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_s != null && env_o.agt_s.slv_sqr != null) begin
            odve_rffe_slv_mem_seq responder = odve_rffe_slv_mem_seq::type_id::create("responder");
            responder.nregs = env_o.cc_o.nregs;
            fork
                responder.start(env_o.agt_s.slv_sqr);
            join_none
        end
    endtask

    // a random sequence on both slaves, the kinds in kind_mask
    function odve_rffe_base_seq rand_seq(string name, int unsigned n, bit [6:0] kind_mask);
        odve_rffe_base_seq s = odve_rffe_base_seq::type_id::create(name);
        s.n         = n;
        s.kind_mask = kind_mask;
        s.usids     = '{env_o.cc_o.usid_prim, env_o.cc_o.usid_sec};
        s.nregs     = env_o.cc_o.nregs;
        return s;
    endfunction

    function odve_rffe_dir_seq dir_seq(string name);
        return odve_rffe_dir_seq::type_id::create(name);
    endfunction

    // n data bytes from the test's stream
    function void bytes(int unsigned n, ref bit [7:0] d[]);
        d = new[n];
        foreach (d[i]) d[i] = 8'(rng.urange(255));
    endfunction

    task run_seq(uvm_sequence #(odve_rffe_item) seq);
        seq.start(env_o.agt.sqr);
    endtask
endclass : base_test
