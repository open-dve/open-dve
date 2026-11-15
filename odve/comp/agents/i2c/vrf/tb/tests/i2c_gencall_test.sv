// General call (UM10204 3.1.13/3.1.14): 06h resets the target's registers
// and pointer (the scoreboard models it, reads back zeros); 04h - writing
// the programmable address - is not supported and NACKed; address 0 with
// R/W = 1 (the START byte) is acknowledged by nobody. REQ-I2C-009.
class i2c_gencall_test extends base_test;
    `uvm_component_utils(i2c_gencall_test)

    function new(string name = "i2c_gencall_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_i2c_item it;
        bit [7:0] d[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        rand_bytes(d, 16);
        wr_regs(0, d);
        rd_regs(5, 3);
        it = mk(I2C_WRITE, 10'h000); it.wdata = '{8'h06}; xfer(it);
        if (!it.addr_ack || it.wr_nack) `uvm_error(get_name(), {"software reset not acknowledged: ", it.convert2string()})
        rd_cur(16);                     // pointer back at 0, all zero
        wr_regs(3, '{8'hA5, 8'h5A});
        it = mk(I2C_WRITE, 10'h000); it.wdata = '{8'h04, 8'h00}; xfer(it);
        if (!it.addr_ack || !it.wr_nack) `uvm_error(get_name(), {"general call 04h should be NACKed: ", it.convert2string()})
        it = mk(I2C_READ, 10'h000); it.nrd = 1; xfer(it);
        if (it.addr_ack) `uvm_error(get_name(), {"START byte acknowledged: ", it.convert2string()})
        rd_regs(3, 2);
        phase.drop_objection(this);
    endtask : run_phase
endclass : i2c_gencall_test
