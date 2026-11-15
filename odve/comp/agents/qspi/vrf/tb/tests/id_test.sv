// Identification and status: JEDEC ID (repeating), SFDP header and the
// density DWORD, status 1/2, WEL set/cleared by WREN/WRDI, QE through write
// status 2, and the same in QPI mode (JEDEC ID memory type 60h there).
class id_test extends base_test;
    `uvm_component_utils(id_test)
    function new(string name = "id_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_qspi_base_seq s = fs("id");
        bit [7:0] d[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        s.rd_reg(QSPI_RDID, 3, d);
        s.rd_reg(QSPI_RDID, 7, d);                 // repeats
        s.read(QSPI_SFDP, 0, 16, d);               // header + parameter header
        s.read(QSPI_SFDP, 'h80, 12, d);            // BFP DWORD1..3
        s.read(QSPI_SFDP, 'hF8, 16, d);            // wraps inside the 256-byte SFDP space
        s.rd_reg(QSPI_RDSR1, 2, d);
        s.op(QSPI_WREN);
        s.rd_reg(QSPI_RDSR1, 1, d);                // WEL = 1
        s.op(QSPI_WRDI);
        s.rd_reg(QSPI_RDSR1, 1, d);                // WEL = 0
        s.rd_reg(QSPI_RDSR2, 1, d);                // QE = 0
        s.write_sr2(8'h02);
        s.rd_reg(QSPI_RDSR2, 2, d);                // QE = 1
        s.enter_qpi();
        s.rd_reg(QSPI_RDID, 6, d);
        s.op(QSPI_WREN);
        s.rd_reg(QSPI_RDSR1, 1, d);
        s.op(QSPI_WRDI);
        s.rd_reg(QSPI_RDSR1, 1, d);
        s.rd_reg(QSPI_RDSR2, 1, d);
        s.exit_qpi();
        s.rd_reg(QSPI_RDID, 3, d);
        s.write_sr2(8'h00);
        s.rd_reg(QSPI_RDSR2, 1, d);                // QE = 0 again
        phase.drop_objection(this);
    endtask : run_phase
endclass : id_test
