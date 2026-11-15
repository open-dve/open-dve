// Errors the monitor must report and commands the flash must refuse; each
// expected report is demoted and counted by expect_catcher, a missing one
// is an error:
//   quad instructions with QE = 0 (6Bh, EBh: ignored, lines undriven -> QSPI_IO_Z;
//   32h, 38h: ignored), cs_n raised mid data byte / inside the address
//   (QSPI_TRUNC, the program is not executed), clocks after a sector erase's
//   address (QSPI_EXTRA, not executed), short tSLCH / tCHSH / tSHSL,
//   sclk off its idle level at cs_n rise, two drivers on io1, an opcode the
//   flash does not know (QSPI_UNK warning).
class err_test extends base_test;
    `uvm_component_utils(err_test)
    expect_catcher ec;
    string ids[$] = '{"QSPI_IO_Z", "QSPI_TRUNC", "QSPI_EXTRA", "QSPI_LEAD", "QSPI_TRAIL", "QSPI_IDLE",
                      "QSPI_CPOL", "QSPI_IO_CONT", "QSPI_UNK"};

    function new(string name = "err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ec = new("ec");
        foreach (ids[i]) ec.expect_id(ids[i]);
        uvm_report_cb::add(null, ec);
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_qspi_base_seq s = fs("err");
        virtual odve_qspi_if vif = env_o.cfg.vif;
        odve_qspi_item it;
        bit [7:0] d[$], w[$];
        bit [7:0] sr;
        super.run_phase(phase);
        phase.raise_objection(this);
        rnd(64, w); s.page_program(QSPI_PP, 24'h000000, w);
        // QE = 0: quad instructions refused
        s.read(QSPI_QOR, 24'h000000, 4, d);
        s.read(QSPI_QIOR, 24'h000000, 4, d);
        rnd(8, w); s.page_program(QSPI_QPP, 24'h000040, w);
        s.op(QSPI_QPIEN);                                         // ignored: bus stays SPI
        s.rd_reg(QSPI_RDID, 3, d);
        s.read(QSPI_READ, 24'h000040, 8, d);
        // cs_n mid data byte: page program not executed
        s.op(QSPI_WREN);
        it = s.new_item(QSPI_PP); it.addr = 24'h000080; rnd(4, it.wdata);
        it.abort_after_clks = 8 + 24 + 8 + 3; s.send(it);
        s.rd_reg(QSPI_RDSR1, 1, d);                               // not busy, WEL still set
        // cs_n inside the address
        it = s.new_item(QSPI_SE); it.addr = 24'h000000; it.abort_after_clks = 20; s.send(it);
        // clocks after a sector erase: not executed
        it = s.new_item(QSPI_SE); it.addr = 24'h000000; it.extra_clks = 2; s.send(it);
        s.rd_reg(QSPI_RDSR1, 1, d);
        s.op(QSPI_WRDI);
        s.read(QSPI_READ, 24'h000000, 160, d);
        // timing
        it = s.new_item(QSPI_RDSR1); it.lead = 1;  s.send(it);
        it = s.new_item(QSPI_RDSR1); it.trail = 1; s.send(it);
        it = s.new_item(QSPI_RDSR1); it.idle = 1;  s.send(it);
        it = s.new_item(QSPI_RDSR2); it.cpol_err = 1; s.send(it);
        // a second driver on io1 during read data
        fork
            s.read(QSPI_READ, 24'h000000, 16, d);
            begin
                wait (vif.cs_n === 1'b0 && (vif.d_io_oe[1] === 1'b1 || vif.s_io_oe[1] === 1'b1));
                @(posedge vif.clk);
                vif.m_io_oe[1] <= 1'b1;
                @(posedge vif.clk);
                vif.m_io_oe[1] <= 1'b0;
            end
        join
        // unknown opcode (Release Power-down is not modelled; FFh is QPI only)
        s.op(8'hAB);
        s.op(QSPI_QPIEX);
        s.rd_reg(QSPI_RDSR2, 1, d);
        s.wait_ready(sr);
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        foreach (ids[i]) begin
            if (ec.seen[ids[i]] == 0) `uvm_error(get_name(), $sformatf("expected report %s did not happen", ids[i]))
            else `uvm_info(get_name(), $sformatf("%s reported %0d time(s), as injected", ids[i], ec.seen[ids[i]]), UVM_LOW)
        end
    endfunction
endclass : err_test
