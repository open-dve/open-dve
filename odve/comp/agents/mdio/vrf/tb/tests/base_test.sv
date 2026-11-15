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

    // With +mdio_slave=seq the slave agent needs a responder: start the
    // register-model sequence in the background before any traffic. It never
    // ends and holds no objection, so the test decides when the run is over.
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_s != null && env_o.agt_s.slv_sqr != null) begin
            odve_mdio_slv_resp_seq responder = odve_mdio_slv_resp_seq::type_id::create("responder");
            responder.model.configure(env_o.cfg_s);
            fork
                responder.start(env_o.agt_s.slv_sqr);
            join_none
        end
    endtask

    // Runs `seq` on the master agent's sequencer (raise/drop around it is the caller's).
    task run_seq(odve_mdio_base_seq seq);
        seq.start(env_o.agt.sqr);
    endtask

    function bit [15:0] u16();
        return 16'(rng.u16());
    endfunction

    // Directed check on a read the test made (the scoreboard checks every
    // frame against its model as well).
    function void expect_rd(odve_mdio_item it, bit resp, bit [15:0] data);
        if (it.resp !== resp || it.data !== data)
            `uvm_error(get_name(), $sformatf("%s: expected %s data 0x%04h", it.convert2string(), resp ? "answer" : "no answer", data))
    endfunction
endclass : base_test
