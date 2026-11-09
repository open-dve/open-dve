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

    // With +apb_slave=seq the slave agent needs a responder: start the
    // memory sequence in the background before any test traffic. It never
    // ends and holds no objection, so the test decides when the run is over.
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_s != null && env_o.agt_s.slv_sqr != null) begin
            odve_apb_slv_mem_seq responder = odve_apb_slv_mem_seq::type_id::create("responder");
            fork
                responder.start(env_o.agt_s.slv_sqr);
            join_none
        end
    endtask

    // Runs `seq` on the master agent's sequencer; subclasses compose their traffic from this.
    task run_seq(odve_apb_base_seq seq);
        seq.start(env_o.agt.sqr);
    endtask
endclass : base_test
