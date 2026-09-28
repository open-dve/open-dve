class read_test extends uvm_test;
    `uvm_component_utils(read_test)

    function new(string name = "red_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        // PHASE-0 SPIKE: this TB has no real traffic yet, so the test itself
        // walks a fixed value pattern (hits one/some/big[8]/zero-ignored, never
        // big[16]); the loop runs with or without FCOV so the two builds can
        // be timed against each other. +cov_iters=N stretches the run.
        int  iters   = 200;
        int  lens[8] = '{1, 2, 3, 4, 8, 0, 1, 2};
`ifdef ODVE_FCOV
        odve_cov_apb_cg cg;
`endif
        super.run_phase(phase);
        `uvm_info(get_name(),"RUN TEST", UVM_NONE)
`ifdef ODVE_FCOV
        cg = new("apb_cg");
`endif
        void'($value$plusargs("cov_iters=%d", iters));
        phase.raise_objection(this);
        for (int i = 0; i < iters; i++) begin
            `odve_cov_sample(cg, lens[i % 8], bit'(i % 2))
            #1;
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : read_test

