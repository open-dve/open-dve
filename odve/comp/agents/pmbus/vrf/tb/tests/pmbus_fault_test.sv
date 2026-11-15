// Communication faults (Part II 10.8, 10.9) and their reporting: each fault
// must give the right acknowledge, set its STATUS_CML bit and STATUS_BYTE.CML,
// assert SMBALERT#; the ARA read returns the address and releases SMBALERT#,
// writing 1s to STATUS_CML clears bits (10.2.4), CLEAR_FAULTS clears all
// (15.1). Cases: unsupported code (manufacturer range and a Table 31 code
// the device lacks), data to a read-only code, invalid data (OPERATION,
// ON_OFF_CONFIG, VOUT_MODE), too many bytes, reading past the PEC, a read
// of the send-only CLEAR_FAULTS, a message starting with a read. The
// PMB_PROTO checks of the monitor are provoked twice (demoted, counted).
// REQ-PMB-011..016.
class pmbus_fault_test extends base_test;
    `uvm_component_utils(pmbus_fault_test)

    function new(string name = "pmbus_fault_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        env_o.agt.mon.set_report_severity_id_override(UVM_ERROR, "PMB_PROTO", UVM_INFO);
    endfunction

    task expect_ack(odve_pmbus_item p, bit ack);
        if (p.ack != ack) `uvm_error(get_name(), $sformatf("%s: expected %s", p.convert2string(), ack ? "ACK" : "a NACK"))
    endtask

    // STATUS_CML must be `cml` and SMBALERT# asserted; then clear
    task expect_fault(bit [7:0] cml, bit by_ara);
        expect_val(PMB_STATUS_CML, {8'h00, cml});
        expect_val(PMB_STATUS_BYTE, 16'h0042);       // OFF, CML
        settle();
        if (!alert_line()) `uvm_error(get_name(), $sformatf("SMBALERT# not asserted (STATUS_CML %02h)", cml))
        if (by_ara) begin
            ara(rng.chance(50));
            settle();
            if (alert_line()) `uvm_error(get_name(), "SMBALERT# still asserted after the ARA")
            wr_byte(PMB_STATUS_CML, cml);            // clear exactly these bits
            expect_val(PMB_STATUS_CML, 16'h0000);
        end else begin
            send_byte(PMB_CLEAR_FAULTS);
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_pmbus_item p;
        bit [7:0] msg[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        expect_val(PMB_STATUS_CML, 16'h0000);

        p = mk(PMB_WRITE, 8'hD3); p.wdata = '{8'h12}; send(p); expect_ack(p, 0);        // 10.9.2
        expect_fault(8'h80, 1);
        p = mk(PMB_WRITE, PMB_VOUT_TRIM, 1); p.wdata = '{8'h00, 8'h01}; send(p); expect_ack(p, 0);
        expect_fault(8'h80, 0);
        p = mk(PMB_READ, 8'hD7); send(p); expect_ack(p, 0);
        expect_fault(8'h80, 1);
        p = mk(PMB_WRITE, PMB_READ_VOUT); p.wdata = '{8'h00, 8'h02}; p.force_proto = SMB_WRITE_WORD; send(p); expect_ack(p, 0);
        expect_fault(8'h80, 0);

        p = mk(PMB_WRITE, PMB_OPERATION); p.wdata = '{8'hA8}; send(p); expect_ack(p, 1);  // margin high: unsupported (10.9.3)
        expect_val(PMB_OPERATION, 16'h0000);
        expect_fault(8'h40, 1);
        p = mk(PMB_WRITE, PMB_ON_OFF_CONFIG, 1); p.wdata = '{8'hF8}; send(p); expect_ack(p, 1);
        expect_fault(8'h40, 0);
        p = mk(PMB_WRITE, PMB_VOUT_MODE); p.wdata = '{8'h40}; send(p); expect_ack(p, 1);   // 8.3.1
        expect_val(PMB_VOUT_MODE, 16'h0017);
        expect_fault(8'h40, 1);

        // too many bytes (10.8.5): OPERATION + a byte that is a correct PEC + the host's PEC
        msg = '{{DEV_ADDR, 1'b0}, PMB_OPERATION, 8'h88};
        p = mk(PMB_WRITE, PMB_OPERATION, 1); p.wdata = '{8'h88, odve_smbus_pec(msg)}; p.force_proto = SMB_WRITE_WORD;
        send(p); expect_ack(p, 0);
        expect_val(PMB_OPERATION, 16'h0000);           // not carried out
        expect_fault(8'h40, 0);

        // reading too many bytes (10.8.6): a byte command read as a word with PEC
        p = mk(PMB_READ, PMB_PMBUS_REVISION, 1); p.force_proto = SMB_READ_WORD; send(p);
        expect_fault(8'h02, 1);
        // a read of a send-only code, a message starting with a read (10.9.1)
        p = mk(PMB_READ, PMB_CLEAR_FAULTS); p.force_proto = SMB_READ_BYTE; send(p);
        expect_fault(8'h80, 0);
        p = mk(PMB_READ, 8'h00); p.force_proto = SMB_RECV_BYTE; send(p);
        if (p.rdata.size() != 1 || p.rdata[0] != 8'hFF) `uvm_error(get_name(), {"read at START should return FFh: ", p.convert2string()})
        expect_fault(8'h02, 1);
        // several faults at once, then CLEAR_FAULTS
        p = mk(PMB_WRITE, 8'hDE); p.wdata = '{8'h00}; send(p);
        wr_byte(PMB_PAGE, 8'h09);
        expect_fault(8'hC0, 0);
        settle();
        if (alert_line()) `uvm_error(get_name(), "SMBALERT# still asserted after CLEAR_FAULTS")
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.agt.mon.n_proto_err != 2)
            `uvm_error(get_name(), $sformatf("monitor flagged %0d PMB_PROTO errors, expected 2", env_o.agt.mon.n_proto_err))
    endfunction
endclass : pmbus_fault_test
