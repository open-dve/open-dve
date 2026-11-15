// SMBALERT# and the Alert Response Address (SMBus 3.3 A.2): nobody answers
// the ARA while no device alerts; SET_ALERT asserts SMBALERT#, the ARA read
// returns the device's address (with and without PEC) and releases it;
// errors (unsupported command) alert too; CLEAR_STATUS clears STATUS and
// SMBALERT#. The scoreboard checks SMBALERT# after every message.
// REQ-SMB-013, 014.
class smbus_alert_test extends base_test;
    `uvm_component_utils(smbus_alert_test)

    function new(string name = "smbus_alert_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task ara(bit pec, bit exp_ack);
        odve_smbus_item m = mk(SMB_ARA, 8'h00, pec, SMB_ARA_ADDR);
        send(m);
        if (m.addr_ack != exp_ack) `uvm_error(get_name(), {"unexpected ARA answer: ", m.convert2string()})
        if (exp_ack && (m.rdata.size() == 0 || m.rdata[0] != {DEV_ADDR, 1'b0}))
            `uvm_error(get_name(), {"ARA did not return the device address: ", m.convert2string()})
    endtask

    virtual task run_phase(uvm_phase phase);
        bit [7:0] st;
        bit [7:0] d[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        ara(0, 0);
        msg(SMB_SEND_BYTE, 8'h41);                      // SET_ALERT
        settle();
        if (!alert_line()) `uvm_error(get_name(), "SMBALERT# not asserted by SET_ALERT")
        get_status(st);
        ara(0, 1);
        settle();
        if (alert_line()) `uvm_error(get_name(), "SMBALERT# still asserted after the ARA")
        ara(0, 0);
        msg(SMB_SEND_BYTE, 8'h41, none, 1);
        ara(1, 1);
        rand_bytes(d, 1);
        msg(SMB_WRITE_BYTE, 8'h55, d);                  // unsupported: NACK, CMD_ERR, alert
        get_status(st);
        if (st[1] !== 1'b1) `uvm_error(get_name(), $sformatf("STATUS 0x%02h: CMD_ERR not set", st))
        msg(SMB_SEND_BYTE, 8'h40);                      // CLEAR_STATUS releases SMBALERT# too
        settle();
        if (alert_line()) `uvm_error(get_name(), "SMBALERT# still asserted after CLEAR_STATUS")
        get_status(st);
        if (st != 8'h80) `uvm_error(get_name(), $sformatf("STATUS 0x%02h after CLEAR_STATUS, expected 0x80", st))
        phase.drop_objection(this);
    endtask : run_phase
endclass : smbus_alert_test
