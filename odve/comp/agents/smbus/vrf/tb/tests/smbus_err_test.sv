// Message errors: an unsupported command code (written and read) is NACKed;
// a block byte count above 32 is NACKed; reading a Send-Byte-only code is
// answered (ACK) but flagged; a message shorter than its protocol (Write
// Word with one data byte) is not carried out and is no error. STATUS.CMD_ERR
// and SMBALERT# follow. REQ-SMB-016, 017.
class smbus_err_test extends base_test;
    `uvm_component_utils(smbus_err_test)

    function new(string name = "smbus_err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_smbus_item m;
        bit [7:0] d[$], st;
        super.run_phase(phase);
        phase.raise_objection(this);
        rand_bytes(d, 2); msg(SMB_WRITE_WORD, 8'h10, d);
        rand_bytes(d, 1); msg(SMB_WRITE_BYTE, 8'h7E, d, 1);     // unsupported
        msg(SMB_READ_BYTE, 8'h99, none, 1);                       // unsupported, read
        get_status(st);
        if (st[1] !== 1'b1) `uvm_error(get_name(), $sformatf("STATUS 0x%02h: CMD_ERR not set", st))
        msg(SMB_SEND_BYTE, 8'h40);
        rand_bytes(d, 33); msg(SMB_BLOCK_WRITE, 8'h30, d);        // count 33 > 32
        msg(SMB_BLOCK_READ, 8'h30, none, 1);
        msg(SMB_SEND_BYTE, 8'h40);
        msg(SMB_READ_BYTE, 8'h41);                                // a Send Byte code, read
        get_status(st);
        if (st[1] !== 1'b1) `uvm_error(get_name(), $sformatf("STATUS 0x%02h: CMD_ERR not set by a read of a send-only code", st))
        msg(SMB_SEND_BYTE, 8'h40);
        m = mk(SMB_WRITE_WORD, 8'h10);                            // one data byte only
        rand_bytes(m.wdata, 1);
        send(m);
        msg(SMB_READ_WORD, 8'h10, none, 1);                       // unchanged
        get_status(st);
        if (st != 8'h80) `uvm_error(get_name(), $sformatf("STATUS 0x%02h: a short message must not be an error", st))
        phase.drop_objection(this);
    endtask : run_phase
endclass : smbus_err_test
