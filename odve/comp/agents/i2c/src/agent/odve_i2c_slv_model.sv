// The behaviour of an I2C target, separated from the bit-level slave driver
// so the same model serves both slave modes: the driver calls it directly
// (ODVE_I2C_SLV_MEM, cfg.model), or a responding sequence holds it
// (ODVE_I2C_SLV_SEQ, seq/odve_i2c_slv_model_seq.sv). SMBus/PMBus device
// models extend this class. handle() answers one event in zero time.
class odve_i2c_slv_model extends uvm_object;
    `uvm_object_utils(odve_i2c_slv_model)

    function new(string name = "odve_i2c_slv_model");
        super.new(name);
    endfunction

    // Extra 7-bit addresses the target answers besides cfg.addr7/addr10 and
    // the general call (e.g. the SMBus Alert Response Address while alerting).
    virtual function bit claims(bit [6:0] a7);
        return 0;
    endfunction

    // Default: acknowledge everything, read 0xFF, no stretching.
    virtual function void handle(odve_i2c_slv_item ev);
        ev.ack     = 1;
        ev.stretch = 0;
        if (ev.ev == I2C_EV_READ) ev.data = 8'hFF;
    endfunction
endclass

// The register-file target of this agent's TB, EEPROM style - the same
// behaviour as the RTL in vrf/dut:
//   * nregs (16) byte registers; the first byte written after the address is
//     the register pointer (NACKed when >= nregs), the following bytes are
//     written from there, reads read from there; the pointer increments after
//     every byte and wraps; it is kept between transfers (current-address read)
//   * general call 06h: software reset (registers and pointer to 0); any
//     other second byte is NACKed
//   * register nregs-1 is CTRL: bits [5:0] = SCL stretch, in cycles, after
//     every acknowledge of a continuing transfer.
class odve_i2c_mem_model extends odve_i2c_slv_model;
    `uvm_object_utils(odve_i2c_mem_model)

    int unsigned nregs = 16;
    bit [7:0]    regs[];
    int unsigned ptr = 0;
    bit          in_gc = 0;

    function new(string name = "odve_i2c_mem_model");
        super.new(name);
        sw_reset();
    endfunction

    function void sw_reset();
        regs = new[nregs];
        foreach (regs[i]) regs[i] = 8'h00;
        ptr = 0;
    endfunction

    function int unsigned stretch_cycles();
        return regs[nregs - 1] & 8'h3F;
    endfunction

    virtual function void handle(odve_i2c_slv_item ev);
        if (regs.size() != nregs) sw_reset();
        ev.ack = 1;
        case (ev.ev)
            I2C_EV_ADDR: in_gc = ev.gc;
            I2C_EV_WRITE: begin
                if (in_gc) begin
                    ev.ack = (ev.idx == 0 && ev.data == 8'h06);
                    if (ev.ack) sw_reset();
                end else if (ev.idx == 0) begin
                    ev.ack = ev.data < nregs;
                    if (ev.ack) ptr = ev.data;
                end else begin
                    regs[ptr] = ev.data;
                    ptr = (ptr + 1) % nregs;
                end
            end
            I2C_EV_READ: begin
                ev.data = regs[ptr];
                ptr = (ptr + 1) % nregs;
            end
            default: in_gc = 0;
        endcase
        ev.stretch = stretch_cycles();
    endfunction
endclass
