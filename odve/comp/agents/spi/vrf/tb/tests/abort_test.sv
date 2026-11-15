// cs_n raised in the middle of a word (and of the command word): the slave
// must drop the incomplete word and keep every complete one; read-backs show
// it (scoreboard), and the monitor reports the partial word.
class abort_test extends base_test;
    `uvm_component_utils(abort_test)
    function new(string name = "abort_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_spi_reg_seq s = reg_seq("abort");
        odve_spi_item    it;
        bit [31:0]       rd[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        for (int k = 0; k < 24; k++) begin
            int unsigned cs   = k % 2;
            int unsigned W    = env_o.cfg.dev[cs].word_bits;
            int unsigned addr = rng.below(64);
            int unsigned nw   = rng.urand(1, 4);
            bit [31:0]   wd[$];
            int          cut;
            repeat (nw) begin
                bit [31:0] v = rng.u32();
                wd.push_back(v);
            end
            // cut anywhere strictly inside the frame but not on a word boundary
            do cut = rng.urand(1, (nw + 1) * W - 1); while (cut % W == 0);
            s.xfer(cs, rng.chance(30), addr, wd, it, 0, cut);
            s.read(cs, addr, nw, rd);
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : abort_test
