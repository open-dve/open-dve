// Program and erase: page program 1-1-1, quad page program 1-1-4 and QPI
// page program 4-4-4, programming over programmed bytes (bits only clear),
// a program wrapping inside its page and one longer than a page, programs
// without WEL (ignored), sector erase of both sectors; reads check it all.
class prog_test extends base_test;
    `uvm_component_utils(prog_test)
    function new(string name = "prog_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_qspi_base_seq s = fs("pg");
        bit [7:0] d[$];
        bit [7:0] sr;
        super.run_phase(phase);
        phase.raise_objection(this);
        for (int i = 0; i < 6; i++) begin
            rnd(rng.urand(1, 64), d);
            s.page_program(QSPI_PP, rng.below(8192), d);
        end
        rnd(32, d); s.page_program(QSPI_PP, 24'h000300, d);
        rnd(32, d); s.page_program(QSPI_PP, 24'h000300, d);        // over programmed bytes: AND
        s.read(QSPI_READ, 24'h000300, 32, d);
        rnd(100, d); s.page_program(QSPI_PP, 24'h0004C8, d);       // 200 + 100 > 256: wraps to 0x400
        rnd(300, d); s.page_program(QSPI_PP, 24'h000610, d);       // longer than a page: overwrites itself
        s.read(QSPI_FREAD, 24'h000400, 256, d);
        s.read(QSPI_FREAD, 24'h000600, 256, d);
        // no WEL: ignored
        rnd(16, d); s.page_program(QSPI_PP, 24'h000700, d, 0);
        s.op(QSPI_WREN); s.op(QSPI_WRDI);
        rnd(16, d); s.page_program(QSPI_PP, 24'h000710, d, 0);
        s.erase(24'h000123, 0);
        s.read(QSPI_READ, 24'h000700, 32, d);
        // quad
        s.write_sr2(8'h02);
        rnd(256, d); s.page_program(QSPI_QPP, 24'h001200, d);
        rnd(77, d);  s.page_program(QSPI_QPP, 24'h001380, d);
        s.read(QSPI_QIOR, 24'h001200, 512, d);
        s.enter_qpi();
        rnd(256, d); s.page_program(QSPI_PP, 24'h001500, d);
        rnd(20, d);  s.page_program(QSPI_PP, 24'h0015F8, d);       // QPI program wrapping in its page
        s.read(QSPI_QIOR, 24'h001500, 256, d);
        s.erase(24'h001ABC);                                  // sector 1, in QPI
        s.read(QSPI_FREAD, 24'h001000, 64, d);
        s.exit_qpi();
        s.erase(24'h000ABC);                                  // sector 0
        s.read(QSPI_READ, 24'h000000, 300, d);
        s.read(QSPI_QOR, 24'h001F80, 200, d);
        s.wait_ready(sr);
        phase.drop_objection(this);
    endtask : run_phase
endclass : prog_test
