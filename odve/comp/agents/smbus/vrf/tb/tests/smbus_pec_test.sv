// PEC errors (SMBus 3.3 6.4): a wrong PEC on every write protocol must be
// NACKed by the device, the message dropped (the register keeps its value),
// STATUS.PEC_ERR set and SMBALERT# asserted; the monitor must flag each
// mismatch (SMB_PEC, demoted and counted here). Against the slave agent the
// device side is corrupted too (model.bad_rd_pec): the host and the monitor
// must catch a wrong PEC on reads. REQ-SMB-011, 012, 016.
class smbus_pec_test extends base_test;
    `uvm_component_utils(smbus_pec_test)

    int unsigned n_inj = 0;

    function new(string name = "smbus_pec_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        env_o.agt.mon.set_report_severity_id_override(UVM_ERROR, "SMB_PEC", UVM_INFO);
    endfunction

    task bad(odve_smbus_proto_e p, bit [7:0] cmd, bit [7:0] w[$]);
        odve_smbus_item m = mk(p, cmd, 1);
        m.wdata   = w;
        m.bad_pec = 1;
        send(m);
        n_inj++;
        if (m.ack) `uvm_error(get_name(), {"wrong PEC not NACKed: ", m.convert2string()})
    endtask

    virtual task run_phase(uvm_phase phase);
        bit [7:0] d[$], st;
        super.run_phase(phase);
        phase.raise_objection(this);
        rand_bytes(d, 1); msg(SMB_WRITE_BYTE, 8'h03, d, 1);
        rand_bytes(d, 2); msg(SMB_WRITE_WORD, 8'h11, d, 1);
        rand_bytes(d, 6); msg(SMB_BLOCK_WRITE, 8'h30, d, 1);

        rand_bytes(d, 1); bad(SMB_WRITE_BYTE, 8'h03, d);
        msg(SMB_READ_BYTE, 8'h03, none, 1);            // unchanged
        rand_bytes(d, 2); bad(SMB_WRITE_WORD, 8'h11, d);
        msg(SMB_READ_WORD, 8'h11, none, 1);
        rand_bytes(d, 9); bad(SMB_BLOCK_WRITE, 8'h30, d);
        msg(SMB_BLOCK_READ, 8'h30, none, 1);
        bad(SMB_SEND_BYTE, 8'h41, none);                // SET_ALERT not carried out ...
        get_status(st);                                 // ... but the PEC error alerts
        if (st[0] !== 1'b1 || st[2] !== 1'b0) `uvm_error(get_name(), $sformatf("STATUS 0x%02h: expected PEC_ERR and no ALERT_REQ", st))
        settle();
        if (!alert_line()) `uvm_error(get_name(), "SMBALERT# not asserted after a PEC error")
        send(mk(SMB_ARA, 8'h00, 1, SMB_ARA_ADDR));
        msg(SMB_SEND_BYTE, 8'h40, none, 1);

        if (env_o.agt_s != null) begin                  // the device's PEC, wrong
            odve_smbus_item m;
            env_o.agt_s.cfg.model.bad_rd_pec = 1;
            m = mk(SMB_READ_WORD, 8'h11, 1); send_bad_rd(m);
            m = mk(SMB_BLOCK_READ, 8'h30, 1); send_bad_rd(m);
            m = mk(SMB_RECV_BYTE, 8'h00, 1); send_bad_rd(m);
            env_o.agt_s.cfg.model.bad_rd_pec = 0;
            msg(SMB_READ_WORD, 8'h11, none, 1);
        end
        phase.drop_objection(this);
    endtask : run_phase

    task send_bad_rd(odve_smbus_item m);
        m.bad_pec = 1;      // tells send() the wrong PEC is expected
        send(m);
        n_inj++;
        if (m.pec_ok) `uvm_error(get_name(), {"host did not see the device's wrong PEC: ", m.convert2string()})
    endtask

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (env_o.agt.mon.n_pec_err != n_inj)
            `uvm_error(get_name(), $sformatf("%0d PEC errors injected, monitor flagged %0d", n_inj, env_o.agt.mon.n_pec_err))
    endfunction
endclass : smbus_pec_test
