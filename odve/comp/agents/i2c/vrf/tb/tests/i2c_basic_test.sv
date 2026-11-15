// 7-bit addressing: register writes, combined-format reads, current-address
// reads, a pointer-only write, single-byte transfers. REQ-I2C-001..006, 009, 010.
class i2c_basic_test extends base_test;
    `uvm_component_utils(i2c_basic_test)

    function new(string name = "i2c_basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        bit [7:0] d[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        rand_bytes(d, 4);
        wr_regs(2, d);              // regs 2..5
        rd_regs(2, 4);              // read them back
        rd_cur(2);                  // regs 6, 7 (pointer continues)
        rand_bytes(d, 1);
        wr_regs(14, d);             // one byte, register 14
        wr_regs(0, none);           // pointer only
        rd_cur(1);                  // register 0
        rand_bytes(d, 16);
        wr_regs(0, d);              // the whole file
        rd_regs(0, 16);
        rd_regs(15, 1);             // last register
        phase.drop_objection(this);
    endtask : run_phase
endclass : i2c_basic_test
