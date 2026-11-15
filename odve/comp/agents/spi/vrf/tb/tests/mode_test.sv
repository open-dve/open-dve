// Every format on both chip selects: the four modes x MSB/LSB first x 8/16/32-bit
// words, each with a write + read-back of a few words and some random traffic.
class mode_test extends base_test;
    `uvm_component_utils(mode_test)
    function new(string name = "mode_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spi_reg_seq s = reg_seq("mode");
        int unsigned bits[3] = '{8, 16, 32};
        super.run_phase(phase);
        phase.raise_objection(this);
        for (int cs = 0; cs < 2; cs++)
            for (int m = 0; m < 4; m++)
                for (int l = 0; l < 2; l++)
                    foreach (bits[b]) begin
                        fmt(cs, m[1], m[0], l[0], bits[b]);
                        wr_rd(s, cs, rng.below(64), rng.urand(1, 3));
                        s.cs = cs;
                        s.n  = 2;
                        s.max_words = 4;
                        run_seq(s);
                    end
        phase.drop_objection(this);
    endtask : run_phase
endclass : mode_test
