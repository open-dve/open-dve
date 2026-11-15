// Every read instruction on the same data: pages programmed with random
// bytes (first page, a middle page, the last page of the array), then read
// back with 03h, 0Bh, 3Bh, BBh, 6Bh, EBh in SPI mode and 0Bh, EBh in QPI:
// single bytes, page-crossing reads, reads wrapping from the end of the
// array to address 0. Run in SPI mode 0 and 3 (+qspi_mode).
class read_test extends base_test;
    `uvm_component_utils(read_test)
    function new(string name = "read_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task read_all(odve_qspi_base_seq s, bit [7:0] cmds[$]);
        bit [7:0] d[$];
        foreach (cmds[i]) begin
            s.read(cmds[i], 24'h000000, 1, d);
            s.read(cmds[i], 24'h0000F0, 40, d);               // page 0 -> 1
            s.read(cmds[i], 24'h000A00 + rng.below(256), rng.urand(1, 64), d);
            s.read(cmds[i], 24'h001FE0, 48, d);               // end of the array -> 0
            s.read(cmds[i], 24'hFF1F00 + rng.below(256), 8, d);   // address bits above the array ignored
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_qspi_base_seq s = fs("rd");
        bit [7:0] d[$];
        bit [7:0] spi_cmds[$] = '{QSPI_READ, QSPI_FREAD, QSPI_DOR, QSPI_DIOR, QSPI_QOR, QSPI_QIOR};
        bit [7:0] qpi_cmds[$] = '{QSPI_FREAD, QSPI_QIOR};
        super.run_phase(phase);
        phase.raise_objection(this);
        rnd(256, d); s.page_program(QSPI_PP, 24'h000000, d);
        rnd(256, d); s.page_program(QSPI_PP, 24'h000100, d);
        rnd(256, d); s.page_program(QSPI_PP, 24'h000A00, d);
        rnd(256, d); s.page_program(QSPI_PP, 24'h001F00, d);
        s.write_sr2(8'h02);                                   // QE for 6Bh / EBh
        read_all(s, spi_cmds);
        s.enter_qpi();
        read_all(s, qpi_cmds);
        s.exit_qpi();
        phase.drop_objection(this);
    endtask : run_phase
endclass : read_test
