// Functional-coverage model of this test (doc/fcov-plan.md 4.1): a real
// covergroup in standard syntax, at package scope. With FCOV=1 the build's
// `acov` step (covgen.py scan) turns it into odve_cov_pkg::odve_cov_apb_cg;
// a tool with covergroup support could compile this block as it is.
`ifdef ODVE_COV_NATIVE
covergroup apb_cg with function sample(int len, bit dir);
    cp_len: coverpoint len { bins one = {1}; bins some = {[2:4]}; bins big[] = {8, 16};
                             ignore_bins zero = {0}; illegal_bins bad = {[256:$]}; }
    cp_dir: coverpoint dir { bins rd = {0}; bins wr = {1}; }
    x_len_dir: cross cp_len, cp_dir;
endgroup

// Second group: every other bin kind the subset supports, on the same values
// (transition, wildcard, default, iff, cross filter) - a pilot for those.
covergroup apb_cg2 with function sample(int len, bit dir);
    cp_tr: coverpoint len { bins up12 = (1 => 2); bins up23 = (2 => 3); bins down = (8 => 0);
                            bins hop[] = (3 => 4, 4 => 8); }
    cp_w:  coverpoint len { wildcard bins low = {8'b0000_0???}; bins eight = {8}; bins rest = default; }
    cp_en: coverpoint dir iff (len) { bins rd = {0}; bins wr = {1}; }
    x_w_en: cross cp_w, cp_en { ignore_bins ig = binsof(cp_w.eight) && binsof(cp_en.wr); }
endgroup
`endif

class read_test extends uvm_test;
    `uvm_component_utils(read_test)
    `odve_cov_create(apb_cg)
    `odve_cov_create(apb_cg2)

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
        super.run_phase(phase);
        `uvm_info(get_name(),"RUN TEST", UVM_NONE)
        void'($value$plusargs("cov_iters=%d", iters));
        phase.raise_objection(this);
        for (int i = 0; i < iters; i++) begin
            `odve_cov_sample(apb_cg, lens[i % 8], bit'(i % 2))
            `odve_cov_sample(apb_cg2, lens[i % 8], bit'(i % 2))
            #1;
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : read_test

