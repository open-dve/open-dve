// PEC with PMBus (Part II 10.8.1, SMBus 6.4): every command read and written
// with PEC; then each writable command with a wrong PEC: NACKed, not carried
// out, STATUS_CML bit 5, SMBALERT#. The monitor's SMB_PEC check is demoted
// and counted. REQ-PMB-012, 017.
class pmbus_pec_test extends base_test;
    `uvm_component_utils(pmbus_pec_test)

    int unsigned n_inj = 0;

    function new(string name = "pmbus_pec_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        env_o.agt.smb.mon.set_report_severity_id_override(UVM_ERROR, "SMB_PEC", UVM_INFO);
    endfunction

    task bad(odve_pmbus_op_e op, bit [7:0] cmd, bit [7:0] d[$], bit [7:0] exp_cml = 8'h20);
        odve_pmbus_item p = mk(op, cmd, 1);
        p.wdata   = d;
        p.bad_pec = 1;
        send(p);
        n_inj++;
        if (p.ack) `uvm_error(get_name(), {"wrong PEC not NACKed: ", p.convert2string()})
        expect_val(PMB_STATUS_CML, {8'h00, exp_cml}, 1);
        send_byte(PMB_CLEAR_FAULTS, 1);
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_pmbus_item p;
        bit [7:0] cmds[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        cmds = '{PMB_PAGE, PMB_OPERATION, PMB_ON_OFF_CONFIG, PMB_CAPABILITY, PMB_VOUT_MODE, PMB_VOUT_COMMAND,
                 PMB_STATUS_BYTE, PMB_STATUS_WORD, PMB_STATUS_CML, PMB_READ_VOUT, PMB_READ_IOUT, PMB_PMBUS_REVISION};
        foreach (cmds[i]) rd(cmds[i], p, 1);
        wr_byte(PMB_OPERATION, 8'h88, 1);
        wr_word(PMB_VOUT_COMMAND, 16'h0280, 1);

        bad(PMB_WRITE, PMB_PAGE, '{8'h01});
        expect_val(PMB_PAGE, 16'h0000, 1);
        bad(PMB_WRITE, PMB_OPERATION, '{8'h08});
        expect_val(PMB_OPERATION, 16'h0088, 1);
        bad(PMB_WRITE, PMB_ON_OFF_CONFIG, '{8'h00});
        bad(PMB_WRITE, PMB_VOUT_COMMAND, '{8'h00, 8'h03});
        expect_val(PMB_VOUT_COMMAND, 16'h0280, 1);
        expect_val(PMB_READ_VOUT, 16'h0280, 1);
        wr_byte(PMB_PAGE, 8'h09);                     // invalid data, CML bit 6 ...
        bad(PMB_WRITE, PMB_STATUS_CML, '{8'h40}, 8'h60);   // ... not cleared by a write with a wrong PEC
        bad(PMB_SEND, PMB_CLEAR_FAULTS, none);
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.agt.smb.mon.n_pec_err != n_inj)
            `uvm_error(get_name(), $sformatf("%0d wrong PECs sent, monitor flagged %0d", n_inj, env_o.agt.smb.mon.n_pec_err))
    endfunction
endclass : pmbus_pec_test
