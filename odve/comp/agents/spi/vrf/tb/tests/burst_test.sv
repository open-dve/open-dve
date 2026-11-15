// Multi-word frames and address boundaries: the whole 64-byte file in one
// frame per width, accesses wrapping from byte 63 to 0, longer-than-the-file
// bursts, command-only frames, idle sclk gaps between words under one cs_n.
class burst_test extends base_test;
    `uvm_component_utils(burst_test)
    function new(string name = "burst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spi_reg_seq s = reg_seq("burst");
        bit [31:0] none[$];
        bit [31:0] rd[$];
        int unsigned bits[3] = '{8, 16, 32};
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (bits[b]) begin
            int unsigned B = bits[b] / 8;
            fmt(0, 0, 0, 0, bits[b]);
            fmt(1, 1, 1, 1, bits[b]);
            for (int cs = 0; cs < 2; cs++) begin
                wr_rd(s, cs, 0, 64 / B);                           // the whole file
                wr_rd(s, cs, 64 - B, 2);                           // wraps 63 -> 0
                wr_rd(s, cs, 61, 3, 3);                            // unaligned, wraps, with gaps
                s.read(cs, 5, 64 / B + 3, rd);                     // longer than the file
                wr_rd(s, cs, 7, 64 / B + 2);                       // write longer than the file: wraps over itself
                s.write(cs, 10, none);                             // command only
                s.read(cs, 0, 0, rd);
                wr_rd(s, cs, rng.below(64), 1);                    // a single word
            end
            s.cs = -1;
            s.n = 6;
            s.max_words = 20;
            s.gap_pct = 50;
            run_seq(s);
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : burst_test
