// What the target (slave driver) saw, and the answer it needs - one item
// per event, request and response in the same object:
//   I2C_EV_ADDR   its address (or a general call) was received: ack?
//   I2C_EV_WRITE  a byte was written to it: ack?
//   I2C_EV_READ   the controller wants the next byte: data
//   I2C_EV_STOP   the transfer is over (STOP, or aborted/timed out): no answer used
class odve_i2c_slv_item extends uvm_sequence_item;
    `uvm_object_utils(odve_i2c_slv_item)

    odve_i2c_ev_e ev      = I2C_EV_ADDR;
    bit [9:0]     addr    = '0;
    bit           addr10  = 0;
    bit           rw      = 0;       // ADDR: 1 = read
    bit           restart = 0;       // ADDR: after a repeated START
    bit           gc      = 0;       // ADDR: general call
    bit [7:0]     data    = '0;      // WRITE: the byte; READ: the answer
    int unsigned  idx     = 0;       // WRITE/READ: byte index since the address
    bit           mack    = 1;       // READ: the controller ACKed the previous byte (always 1 here)
    bit           abort   = 0;       // STOP: ended inside a byte or by a clock-low timeout
    bit           tmo     = 0;       // STOP: ended by the clock-low timeout
    int unsigned  nrd     = 0;       // STOP: bytes completely transmitted in the last read segment

    // response
    bit           ack     = 1;
    int unsigned  stretch = 0;       // hold SCL low this many cycles after the acknowledge

    function new(string name = "odve_i2c_slv_item");
        super.new(name);
    endfunction

    function string convert2string();
        case (ev)
            I2C_EV_ADDR:  return $sformatf("ADDR 0x%0h%s %s%s -> %s", addr, addr10 ? "(10)" : "", rw ? "R" : "W", restart ? " Sr" : "", ack ? "ACK" : "NACK");
            I2C_EV_WRITE: return $sformatf("WRITE[%0d] %02h -> %s", idx, data, ack ? "ACK" : "NACK");
            I2C_EV_READ:  return $sformatf("READ[%0d] -> %02h", idx, data);
            default:      return $sformatf("STOP%s%s", abort ? " abort" : "", tmo ? " timeout" : "");
        endcase
    endfunction
endclass
