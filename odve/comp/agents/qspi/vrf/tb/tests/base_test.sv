// Builds the env; with +qspi_slave=seq starts the flash's responding
// sequence in the background (never ends, holds no objection). fs() gives a
// flash-operation sequence bound to the master sequencer, whose helpers
// (read/program/erase/...) tests call directly.
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
        rng = new(get_full_name());
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_s != null && env_o.agt_s.slv_sqr != null) begin
            odve_qspi_slv_rsp_seq responder = odve_qspi_slv_rsp_seq::type_id::create("responder");
            fork
                responder.start(env_o.agt_s.slv_sqr);
            join_none
        end
    endtask

    function odve_qspi_base_seq fs(string name = "fs");
        odve_qspi_base_seq s = odve_qspi_base_seq::type_id::create(name);
        s.rng = rng.spawn(name);
        s.set_sequencer(env_o.agt.sqr);
        return s;
    endfunction

    task run_seq(odve_qspi_base_seq seq);
        seq.start(env_o.agt.sqr);
    endtask

    // random bytes from the test's stream
    function void rnd(int unsigned n, output bit [7:0] d[$]);
        d.delete();
        repeat (n) begin
            bit [7:0] b = rng.urange(255);
            d.push_back(b);
        end
    endfunction
endclass : base_test

// Demotes the reports a test provokes on purpose (errors to info, warnings
// too) and counts them, so the test can require each one to have happened.
class expect_catcher extends uvm_report_catcher;
    int unsigned seen [string];
    function new(string name = "expect_catcher");
        super.new(name);
    endfunction
    function void expect_id(string id);
        seen[id] = 0;
    endfunction
    virtual function action_e catch();
        if (get_severity() inside {UVM_ERROR, UVM_WARNING} && seen.exists(get_id())) begin
            seen[get_id()]++;
            set_severity(UVM_INFO);
            set_message({"(expected) ", get_message()});
        end
        return THROW;
    endfunction
endclass
