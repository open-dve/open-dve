// NACK cases (UM10204 3.1.6): absent 7-bit address (write and read), absent
// 10-bit address (header mismatch: A1 NACK; low byte mismatch: A2 NACK), a
// 10-bit read header after START without a preceding write header, register
// pointers out of range (data NACK), and normal traffic in between to show
// the target recovered. REQ-I2C-005, 007, 008.
class i2c_nack_test extends base_test;
    `uvm_component_utils(i2c_nack_test)

    function new(string name = "i2c_nack_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task expect_ack(odve_i2c_item it, bit addr_ack, bit wr_nack);
        if (it.addr_ack != addr_ack || it.wr_nack != wr_nack)
            `uvm_error(get_name(), $sformatf("%s: expected address %s%s", it.convert2string(), addr_ack ? "ACK" : "NACK", wr_nack ? " and a data NACK" : ""))
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_i2c_item it;
        bit [7:0] d[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        rand_bytes(d, 2);
        wr_regs(0, d);

        it = mk(I2C_WRITE, 10'h051);           it.wdata = '{8'h00, 8'h11};  xfer(it); expect_ack(it, 0, 0);
        it = mk(I2C_READ, 10'h033);            it.nrd = 2;                   xfer(it); expect_ack(it, 0, 0);
        it = mk(I2C_WRITE_READ, 10'h05F);      it.wdata = '{8'h00}; it.nrd = 1; xfer(it); expect_ack(it, 0, 0);
        it = mk(I2C_WRITE, 10'h1A5, 1);        it.wdata = '{8'h00};          xfer(it); expect_ack(it, 0, 0);  // header 11110_01 mismatch
        it = mk(I2C_WRITE, 10'h2A6, 1);        it.wdata = '{8'h00};          xfer(it); expect_ack(it, 0, 0);  // low byte mismatch
        it = mk(I2C_WRITE, 10'(TGT_ADDR7));    it.wdata = '{8'h10, 8'h55};   xfer(it); expect_ack(it, 1, 1);  // pointer 16
        it = mk(I2C_WRITE_READ, 10'(TGT_ADDR7)); it.wdata = '{8'hFF}; it.nrd = 1; xfer(it); expect_ack(it, 1, 1);
        it = mk(I2C_WRITE, TGT_ADDR10, 1);     it.wdata = '{8'h80};          xfer(it); expect_ack(it, 1, 1);
        rd_regs(0, 2);
        rd_regs(0, 2, 1);
        phase.drop_objection(this);
    endtask : run_phase
endclass : i2c_nack_test
