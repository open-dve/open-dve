// Protocol violations injected on purpose; the monitor must report each one
// (its uvm_errors are demoted and counted by expect_catcher, a missing one is
// an error): tL / tT / tI too short, sclk off its idle level at cs_n rise,
// two chip selects low at once (which also makes two slaves drive MISO), a
// sampling edge with no MISO driver. The frames are reads of all-ones words,
// so a slave that sees them garbled never writes; normal traffic before and
// after shows the slaves recover.
class err_test extends base_test;
    `uvm_component_utils(err_test)
    expect_catcher ec;
    string ids[$] = '{"SPI_LEAD", "SPI_TRAIL", "SPI_IDLE", "SPI_CPOL", "SPI_MULTI_CS", "SPI_MISO_CONT", "SPI_MISO_Z"};

    function new(string name = "err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ec = new("ec");
        foreach (ids[i]) ec.expect_id(ids[i]);
        uvm_report_cb::add(null, ec);
    endfunction

    task bad(int unsigned cs, int lead = -1, int trail = -1, int idle = -1, bit cpol_err = 0);
        odve_spi_item it = odve_spi_item::type_id::create("bad");
        odve_spi_raw_seq raw;
        it.cs = cs;
        it.word_bits = env_o.cfg.dev[cs].word_bits;
        repeat (3) it.mosi.push_back(it.mask());
        it.lead = lead; it.trail = trail; it.idle = idle; it.cpol_err = cpol_err;
        raw = odve_spi_raw_seq::type_id::create("raw");
        raw.items.push_back(it);
        run_seq(raw);
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_spi_reg_seq s = reg_seq("err");
        virtual odve_spi_if vif = env_o.cfg.vif;
        super.run_phase(phase);
        phase.raise_objection(this);
        s.n = 10; run_seq(s);
        bad(1, 1);                   // tL
        bad(0, -1, 1);               // tT
        bad(0, -1, -1, 1);           // tI (this frame's cs_n high time before the next)
        bad(0);
        bad(1, -1, -1, -1, 1);       // sclk off idle at cs_n rise
        // second chip select pulled low by hand during a cs0 frame
        fork
            bad(0);
            begin
                repeat (12) @(posedge vif.clk);
                vif.cs_n[1] <= 1'b0;
                repeat (20) @(posedge vif.clk);
                vif.cs_n[1] <= 1'b1;
            end
        join
        // a frame on a chip select with nobody behind it: undriven MISO
        env_o.cfg.ncs = 3;
        bad(2);
        env_o.cfg.ncs = 2;
        s.n = 10; run_seq(s);
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        foreach (ids[i]) begin
            if (ec.seen[ids[i]] == 0) `uvm_error(get_name(), $sformatf("expected protocol error %s was not reported", ids[i]))
            else `uvm_info(get_name(), $sformatf("%s reported %0d time(s), as injected", ids[i], ec.seen[ids[i]]), UVM_LOW)
        end
    endfunction
endclass : err_test
