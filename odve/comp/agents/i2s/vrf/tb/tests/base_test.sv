// Builds the env from a cc made here: configure() (the scenario, overridden
// by each test), then the +i2s_* plusargs (tb/env/cc.sv), which win. The run
// sends tc.frames frames from the port A transmitter agent - make_seq()'s
// sequence, or the driver's own generator with SRC_GEN - and then lets the
// buses run 4 more frames so everything in flight reaches the monitors.
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env env_o;
    cc  tc;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    // the scenario: frame format, data source, ... (tc holds the defaults)
    virtual function void configure();
    endfunction

    virtual function odve_i2s_base_seq make_seq();
        return odve_i2s_frame_seq::type_id::create("frames");
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        tc = cc::type_id::create("tc");
        configure();
        tc.apply_plusargs();
        uvm_config_db#(cc)::set(this, "env_o", "tc", tc);
        env_o = env::type_id::create("env_o", this);
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        odve_i2s_base_seq seq;
        super.run_phase(phase);
        phase.raise_objection(this);
        if (tc.src == ODVE_I2S_SRC_SEQ) begin
            seq = make_seq();
            seq.n = tc.frames;
            seq.start(env_o.agt_tx.sqr);
        end else begin
            while (env_o.agt_tx.drv.n_gen < tc.frames) #(tc.frame_ns());
        end
        #(4 * tc.frame_ns());
        phase.drop_objection(this);
    endtask : run_phase
endclass : base_test
