class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env env_o;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_o = env::type_id::create("env_o", this);
    endfunction : build_phase

    // Runs `seq` on the agent's sequencer; subclasses compose their traffic from this.
    task run_seq(odve_apb_base_seq seq);
        seq.start(env_o.agt.sqr);
    endtask
endclass : base_test
