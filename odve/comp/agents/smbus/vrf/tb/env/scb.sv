// Reference model of the SMBus device (written from its definition in
// vrf/dut/dut.sv, independently of the agent's odve_smbus_ref_model),
// checked against every message the host agent's monitor decodes:
//   * address ACK (the device, the ARA only while SMBALERT# is expected)
//   * whether the message was ACKed through: unsupported command, block
//     count > 32 and a wrong PEC must be NACKed, everything else ACKed
//   * every byte read: registers, word registers, process-call results,
//     block register and block process call, STATUS, the ARA answer
//   * SMBALERT# at the end of every message against the expected state
//   * writes take effect only when complete, error free and not timed out
`uvm_analysis_imp_decl(_smbus)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_smbus #(odve_smbus_item, scb) smbus_imp;
    odve_smbus_cfg cfg;

    bit [7:0]  bregs[8];
    bit [15:0] wregs[4];
    bit [7:0]  blk[$];
    bit        st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err, alert;
    int unsigned n_msg = 0, n_rd_bytes = 0, n_commit = 0, n_err = 0, n_nack_exp = 0;

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        smbus_imp = new("smbus_imp", this);
        foreach (bregs[i]) bregs[i] = 8'h00;
        foreach (wregs[i]) wregs[i] = 16'h0000;
    endfunction

    function bit [7:0] status();
        return {1'b1, 2'b00, st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err};
    endfunction

    function void err(odve_smbus_item m, string msg);
        n_err++;
        `uvm_error(get_name(), $sformatf("%s: %s", m.convert2string(), msg))
    endfunction

    function void chk_rd(odve_smbus_item m, bit [7:0] exp[$]);
        if (m.rdata.size() != exp.size()) begin
            err(m, $sformatf("%0d data bytes read, expected %0d", m.rdata.size(), exp.size()));
            return;
        end
        foreach (exp[i]) begin
            n_rd_bytes++;
            if (m.rdata[i] !== exp[i]) err(m, $sformatf("data byte %0d = 0x%02h, expected 0x%02h", i, m.rdata[i], exp[i]));
        end
    endfunction

    function void write_smbus(odve_smbus_item m);
        odve_smbus_cmd_e k;
        bit exp_ack, cmd_err, pec_err, rd_unsup;
        bit [7:0] exp[$];
        n_msg++;
        if (m.alert != alert) err(m, $sformatf("SMBALERT# %s, expected %s", m.alert ? "asserted" : "released", alert ? "asserted" : "released"));

        if (m.addr == SMB_ARA_ADDR) begin
            if (m.addr_ack != alert) err(m, $sformatf("ARA %s while SMBALERT# is %s", m.addr_ack ? "ACKed" : "NACKed", alert ? "expected" : "not expected"));
            if (m.addr_ack) begin
                exp.push_back({DEV_ADDR, 1'b0});
                chk_rd(m, exp);
                if (m.rdata.size() >= 1) alert = 0;
            end
            return;
        end
        if (m.addr != DEV_ADDR) begin
            if (m.addr_ack) err(m, "an absent address was ACKed");
            return;
        end
        if (!m.addr_ack) begin
            err(m, "the device's address was NACKed");
            return;
        end
        if (m.timeout) begin            // the device resets; nothing of the message takes effect
            st_tmo = 1;
            return;
        end
        if (m.aborted) return;

        k = cfg.cmd_tab[m.cmd];
        cmd_err = 0;
        pec_err = 0;
        rd_unsup = 0;
        case (m.proto)
            SMB_QUICK_W: st_quick = 0;
            SMB_QUICK_R: st_quick = 1;
            SMB_RECV_BYTE: begin
                exp.push_back(status());
                chk_rd(m, exp);
            end
            SMB_UNKNOWN: begin
                cmd_err = 1;               // an unsupported code is NACKed; a Send Byte code read is ACKed, answers nothing
                rd_unsup = (k != SMB_CMD_NONE);
            end
            default: begin
                if (m.proto inside {SMB_BLOCK_WRITE, SMB_BLOCK_PROC_CALL} && m.wcount > 32) cmd_err = 1;
                if (m.pec_present && !m.pec_ok && m.proto inside {SMB_SEND_BYTE, SMB_WRITE_BYTE, SMB_WRITE_WORD, SMB_BLOCK_WRITE}) pec_err = 1;   // the host's PEC
            end
        endcase
        exp_ack = !(cmd_err || pec_err) || rd_unsup;
        if (!exp_ack) n_nack_exp++;
        if (m.ack != exp_ack) err(m, $sformatf("message %s, expected %s", m.ack ? "ACKed" : "NACKed", exp_ack ? "ACK" : "NACK"));

        if (exp_ack && m.ack && !rd_unsup) begin
            case (m.proto)
                SMB_READ_BYTE:  exp.push_back(bregs[m.cmd[2:0]]);
                SMB_READ_WORD:  begin exp.push_back(wregs[m.cmd[1:0]][7:0]); exp.push_back(wregs[m.cmd[1:0]][15:8]); end
                SMB_PROC_CALL, SMB_BLOCK_PROC_CALL: foreach (m.wdata[i]) exp.push_back(~m.wdata[i]);
                SMB_BLOCK_READ: foreach (blk[i]) exp.push_back(blk[i]);
                default: ;
            endcase
            if (m.complete && m.proto inside {SMB_BLOCK_READ, SMB_BLOCK_PROC_CALL} && m.count != exp.size())
                err(m, $sformatf("byte count %0d, expected %0d", m.count, exp.size()));
            if (m.complete && m.proto inside {SMB_READ_BYTE, SMB_READ_WORD, SMB_PROC_CALL, SMB_BLOCK_READ, SMB_BLOCK_PROC_CALL})
                chk_rd(m, exp);
            // writes: only complete messages
            if (m.complete && !m.pec_present || m.complete && m.pec_ok) begin
                case (m.proto)
                    SMB_WRITE_BYTE:  begin bregs[m.cmd[2:0]] = m.wdata[0]; n_commit++; end
                    SMB_WRITE_WORD:  begin wregs[m.cmd[1:0]] = {m.wdata[1], m.wdata[0]}; n_commit++; end
                    SMB_BLOCK_WRITE: begin blk = m.wdata; n_commit++; end
                    SMB_SEND_BYTE: begin
                        n_commit++;
                        if (m.cmd == 8'h40) begin
                            {st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err} = '0;
                            alert = 0;
                        end else begin
                            st_alert_req = 1;
                            alert = 1;
                        end
                    end
                    default: ;
                endcase
            end
        end
        if (cmd_err) begin st_cmd_err = 1; alert = 1; end
        if (pec_err) begin st_pec_err = 1; alert = 1; end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d messages checked: %0d bytes read, %0d writes carried out, %0d expected NACKs, %0d errors", n_msg, n_rd_bytes, n_commit, n_nack_exp, n_err), UVM_LOW)
        if (n_msg == 0) `uvm_error(get_name(), "no SMBus messages observed")
    endfunction
endclass : scb
