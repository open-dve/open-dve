// Builds the env; with +spi_slave=seq starts the responding sequence of each
// slave agent in the background (never ends, holds no objection). Helpers:
// reg_seq() for a register-protocol sequence on the master, fmt() to change
// a chip select's format, wr_rd() for a write + read-back with an in-test
// compare (the scoreboard checks every frame independently).
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
        foreach (env_o.agt_s[i]) begin
            if (env_o.agt_s[i] != null && env_o.agt_s[i].slv_sqr != null) begin
                odve_spi_slv_rsp_seq responder = odve_spi_slv_rsp_seq::type_id::create($sformatf("responder%0d", i));
                automatic odve_spi_slv_sqr sqr = env_o.agt_s[i].slv_sqr;
                fork
                    responder.start(sqr);
                join_none
            end
        end
    endtask

    function odve_spi_reg_seq reg_seq(string name = "rs");
        odve_spi_reg_seq s = odve_spi_reg_seq::type_id::create(name);
        s.rng = rng.spawn(name);
        s.set_sequencer(env_o.agt.sqr);      // for the directed helpers (write/read/xfer)
        return s;
    endfunction

    task run_seq(odve_spi_base_seq seq);
        seq.start(env_o.agt.sqr);
    endtask

    function void fmt(int unsigned cs, bit cpol, bit cpha, bit lsb_first, int unsigned bits);
        env_o.set_format(cs, cpol, cpha, lsb_first, bits);
        `uvm_info(get_name(), $sformatf("cs%0d -> %s", cs, env_o.cfg.dev[cs].convert2string()), UVM_MEDIUM)
    endfunction

    // write nwords random words at addr, read them back, compare
    task wr_rd(odve_spi_reg_seq s, int unsigned cs, int unsigned addr, int unsigned nwords, int unsigned gap = 0);
        bit [31:0] wd[$], rd[$];
        bit [31:0] m = (env_o.cfg.dev[cs].word_bits >= 32) ? 32'hFFFF_FFFF : ((32'h1 << env_o.cfg.dev[cs].word_bits) - 1);
        repeat (nwords) begin
            bit [31:0] v = rng.u32();
            wd.push_back(v & m);
        end
        s.write(cs, addr, wd, gap);
        s.read(cs, addr, nwords, rd, gap);
        if (nwords * odve_spi_slv_model::bytes_per_word(env_o.cfg.dev[cs].word_bits) <= 64)   // no self-overlap
            foreach (wd[i])
                if (rd[i] !== wd[i])
                    `uvm_error(get_name(), $sformatf("cs%0d %s addr 0x%02h word %0d: read 0x%0h, wrote 0x%0h",
                                                     cs, env_o.cfg.dev[cs].convert2string(), addr, i, rd[i], wd[i]))
    endtask
endclass : base_test

// Demotes the uvm_errors a test provokes on purpose and counts them, so the
// test can require each of them to have happened.
class expect_catcher extends uvm_report_catcher;
    int unsigned seen [string];
    function new(string name = "expect_catcher");
        super.new(name);
    endfunction
    function void expect_id(string id);
        seen[id] = 0;
    endfunction
    virtual function action_e catch();
        if (get_severity() == UVM_ERROR && seen.exists(get_id())) begin
            seen[get_id()]++;
            set_severity(UVM_INFO);
            set_message({"(expected) ", get_message()});
        end
        return THROW;
    endfunction
endclass
