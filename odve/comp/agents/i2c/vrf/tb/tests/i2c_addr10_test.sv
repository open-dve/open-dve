// 10-bit addressing (UM10204 3.1.11): write (header + low byte + data),
// combined write-read (Sr + header R), read (header W + low byte, Sr, header
// R), mixed with 7-bit access to the same registers. REQ-I2C-007.
class i2c_addr10_test extends base_test;
    `uvm_component_utils(i2c_addr10_test)

    function new(string name = "i2c_addr10_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        bit [7:0] d[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        rand_bytes(d, 6);
        wr_regs(4, d, 1);
        rd_regs(4, 6, 1);
        rd_cur(3, 1);               // 10-bit read: S hdrW a[7:0] Sr hdrR data P
        rd_regs(4, 6, 0);           // the same registers over the 7-bit address
        rand_bytes(d, 3);
        wr_regs(13, d, 0);          // 13, 14, 15 ... and wrap
        rd_regs(13, 5, 1);
        phase.drop_objection(this);
    endtask : run_phase
endclass : i2c_addr10_test
