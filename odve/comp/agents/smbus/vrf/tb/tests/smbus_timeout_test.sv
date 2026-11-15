// Clock-low timeout (SMBus 3.3 4.2.2, scaled: tTIMEOUT,MIN 500 / MAX 700
// cycles, the device resets after 600): the host holds SMBCLK low for 800
// cycles inside a Write Word and inside a Read Word; the device must
// release the bus before tTIMEOUT,MAX (monitor SMB_TIMEOUT check), drop the
// message (the register keeps its value), set STATUS.TMO and answer the
// next message. A 300-cycle hold is no timeout: the device must not reset.
// REQ-SMB-015.
class smbus_timeout_test extends base_test;
    `uvm_component_utils(smbus_timeout_test)

    function new(string name = "smbus_timeout_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_smbus_item m;
        bit [7:0] d[$], st;
        super.run_phase(phase);
        phase.raise_objection(this);
        rand_bytes(d, 2); msg(SMB_WRITE_WORD, 8'h12, d, 1);
        msg(SMB_READ_BYTE, 8'h05);

        m = mk(SMB_WRITE_WORD, 8'h12, 1);               // after the command byte
        rand_bytes(m.wdata, 2);
        m.tmo_byte = 1; m.tmo_cycles = 800;
        send(m);
        msg(SMB_READ_WORD, 8'h12, none, 1);             // unchanged
        get_status(st);
        if (st[4] !== 1'b1) `uvm_error(get_name(), $sformatf("STATUS 0x%02h: TMO not set", st))
        msg(SMB_SEND_BYTE, 8'h40);

        m = mk(SMB_READ_WORD, 8'h12, 1);                // after the first data byte read (device transmitting)
        m.tmo_byte = 3; m.tmo_cycles = 800;
        send(m);
        msg(SMB_READ_WORD, 8'h12, none, 1);

        m = mk(SMB_WRITE_BYTE, 8'h05, 0);               // 300 cycles: below tTIMEOUT,MIN
        rand_bytes(m.wdata, 1);
        m.tmo_byte = 1; m.tmo_cycles = 300;
        send(m);
        msg(SMB_SEND_BYTE, 8'h40);
        m = mk(SMB_WRITE_BYTE, 8'h05, 0);
        rand_bytes(m.wdata, 1);
        m.tmo_byte = 2; m.tmo_cycles = 300;             // then STOP: a complete Write Byte after a long low phase
        send(m);
        msg(SMB_READ_BYTE, 8'h05);
        get_status(st);
        if (st[4] !== 1'b0) `uvm_error(get_name(), $sformatf("STATUS 0x%02h: TMO set by a 300-cycle low phase", st))
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.agt.mon.n_timeout != 2)
            `uvm_error(get_name(), $sformatf("monitor reported %0d timed-out messages, expected 2", env_o.agt.mon.n_timeout))
    endfunction
endclass : smbus_timeout_test
