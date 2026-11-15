// Back-to-back frames at the minimum legal timing (tL = tT = tI = one half
// period) and at several sclk rates, alternating chip selects of different
// formats frame by frame.
class b2b_test extends base_test;
    `uvm_component_utils(b2b_test)
    function new(string name = "b2b_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spi_reg_seq s = reg_seq("b2b");
        int unsigned hp[3] = '{4, 5, 9};
        super.run_phase(phase);
        phase.raise_objection(this);
        fmt(0, 0, 1, 0, 8);
        fmt(1, 1, 0, 1, 32);
        foreach (hp[i]) begin
            env_o.cfg.half_period = hp[i];
            env_o.cfg.lead  = hp[i];
            env_o.cfg.trail = hp[i];
            env_o.cfg.idle  = hp[i];
            s.n = 20;
            s.max_words = 4;
            s.cs = -1;
            run_seq(s);
            for (int k = 0; k < 6; k++) wr_rd(s, k % 2, rng.below(64), 2);
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : b2b_test
