// While a program / erase / status write runs: status 1 shows BUSY and WEL,
// status 2 stays readable, a read and a second program are ignored (the
// read's data lines stay undriven - the undriven check is off for it), a
// long status read sees BUSY fall within the frame, and WEL is clear after.
class busy_test extends base_test;
    `uvm_component_utils(busy_test)
    function new(string name = "busy_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task ignored_read(odve_qspi_base_seq s, bit [7:0] cmd);
        bit [7:0] d[$];
        env_o.cfg.chk_undriven = 0;
        s.read(cmd, 24'h000010, 8, d);
        env_o.cfg.chk_undriven = 1;
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_qspi_base_seq s = fs("busy");
        odve_qspi_item     it;
        bit [7:0] d[$], w[$];
        bit [7:0] sr;
        super.run_phase(phase);
        phase.raise_objection(this);
        rnd(64, w); s.page_program(QSPI_PP, 24'h000000, w);
        // program, then poke it while busy
        s.op(QSPI_WREN);
        it = s.new_item(QSPI_PP); it.addr = 24'h000100; rnd(256, it.wdata); s.send(it);
        s.rd_reg(QSPI_RDSR1, 2, d);
        s.rd_reg(QSPI_RDSR2, 1, d);
        ignored_read(s, QSPI_READ);
        it = s.new_item(QSPI_PP); it.addr = 24'h000200; rnd(16, it.wdata); s.send(it);   // ignored: busy
        s.op(QSPI_WRDI);                                                               // ignored: busy
        s.wait_ready(sr);
        s.read(QSPI_READ, 24'h000100, 300, d);
        // erase, one long status read that sees BUSY fall
        s.op(QSPI_WREN);
        it = s.new_item(QSPI_SE); it.addr = 24'h000000; s.send(it);
        ignored_read(s, QSPI_FREAD);
        s.rd_reg(QSPI_RDSR1, 700, d);
        s.rd_reg(QSPI_RDSR1, 1, d);
        s.read(QSPI_READ, 24'h000000, 300, d);
        // status write busy time
        s.op(QSPI_WREN);
        it = s.new_item(QSPI_WRSR2); it.wdata.push_back(8'h02); s.send(it);
        s.rd_reg(QSPI_RDSR1, 1, d);
        s.wait_ready(sr);
        s.rd_reg(QSPI_RDSR2, 1, d);
        // in QPI
        s.enter_qpi();
        s.op(QSPI_WREN);
        it = s.new_item(QSPI_PP); it.addr = 24'h000400; rnd(32, it.wdata); s.send(it);
        ignored_read(s, QSPI_QIOR);
        s.wait_ready(sr);
        s.read(QSPI_FREAD, 24'h000400, 32, d);
        s.exit_qpi();
        phase.drop_objection(this);
    endtask : run_phase
endclass : busy_test
