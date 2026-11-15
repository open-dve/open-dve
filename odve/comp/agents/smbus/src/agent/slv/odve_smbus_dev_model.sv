// An SMBus target device for the i2c slave driver (odve_i2c_slv_model): the
// SMBus message layer - command code, byte count, PEC checking and
// generation (SMBus 3.3 6.4), protocol lengths (6.5), Quick Command,
// Receive Byte, the Alert Response Address (A.2) - with the device's
// command set left to hooks a concrete device overrides:
//   cmd_kind(cmd)          which protocols a command code is used with
//   wr_ok(cmd) / rd_ok(cmd) the code may be written / read
//   do_write(cmd, d)       a complete, correct write message (at STOP);
//                          d = the bytes after the command (count included)
//   do_read(cmd, w, rsp)   the bytes to return after Sr (count included for
//                          blocks), w = the bytes written after the command
//   recv_byte(ok)          Receive Byte (a read right after START)
//   quick(rw)              Quick Command
//   error(code)            ERR_* below, reported once per message at its end
// Message rules (the same in the RTL engine vrf/dut/odve_smbus_tgt_eng.sv):
//   * unsupported command code: NACKed (ERR_CMD); a data byte written to a
//     read-only code: NACKed (ERR_CMD)
//   * byte count above max_block(): NACKed (ERR_DATA)
//   * a byte after the full message: the PEC when it makes the CRC zero,
//     otherwise NACKed (ERR_PEC); any further byte NACKed (ERR_DATA)
//   * a write is carried out at STOP only when complete and error free; a
//     shorter message is ignored (PMBus Part II 10.8.4)
//   * reads: the response, then the PEC, then FFh; reading past the PEC is
//     ERR_OTHER (PMBus 10.8.6)
//   * a clock-low timeout (ERR_TMO) or a START/STOP inside a byte
//     (ERR_OTHER) drops the message
//   * SMBALERT#: `alert`; while it is set the device answers the ARA with
//     its address and releases `alert` once that byte has been read
class odve_smbus_dev_model extends odve_i2c_slv_model;
    `uvm_object_utils(odve_smbus_dev_model)

    localparam int ERR_CMD = 1, ERR_DATA = 2, ERR_PEC = 3, ERR_OTHER = 4, ERR_TMO = 5;

    bit [6:0] addr  = 7'h3A;
    bit       alert = 0;            // drives SMBALERT# (the agent puts it on the interface)
    bit       bad_rd_pec = 0;       // error injection: send a wrong PEC on reads

    // the message in progress
    protected bit [7:0]        crc;
    protected bit              rd_start, ara, cmd_valid, bad, rd_seg, rsp_ok;
    protected int unsigned     wcnt, rcnt, err_mask;
    protected int              exp_len;      // bytes after the command, -1 = not known yet (block)
    protected bit [7:0]        cmd;
    protected odve_smbus_cmd_e kind;
    protected bit [7:0]        wbuf[$];
    protected bit [7:0]        rsp[$];

    function new(string name = "odve_smbus_dev_model");
        super.new(name);
    endfunction

    // ---- hooks -------------------------------------------------------------
    virtual function odve_smbus_cmd_e cmd_kind(bit [7:0] c); return SMB_CMD_NONE; endfunction
    virtual function bit wr_ok(bit [7:0] c); return 1; endfunction
    virtual function bit rd_ok(bit [7:0] c); return 1; endfunction
    virtual function void do_write(bit [7:0] c, bit [7:0] d[$]); endfunction
    virtual function void do_read(bit [7:0] c, bit [7:0] w[$], ref bit [7:0] r[$]); endfunction
    virtual function bit [7:0] recv_byte(output bit ok); ok = 0; return 8'hFF; endfunction
    virtual function void quick(bit rw); endfunction
    virtual function void error(int code); endfunction
    virtual function int unsigned max_block(); return 32; endfunction

    // ---- engine ------------------------------------------------------------
    virtual function bit claims(bit [6:0] a7);
        return alert && a7 == SMB_ARA_ADDR;
    endfunction

    function void flag(int code);
        err_mask |= (1 << code);
        bad = 1;
    endfunction

    function int len_of(odve_smbus_cmd_e k);
        case (k)
            SMB_CMD_SEND:                return 0;
            SMB_CMD_BYTE:                return 1;
            SMB_CMD_WORD, SMB_CMD_PCALL: return 2;
            SMB_CMD_BLOCK, SMB_CMD_BPCALL: return -1;
            default:                     return 0;
        endcase
    endfunction

    virtual function void handle(odve_i2c_slv_item ev);
        bit [7:0] nc;
        ev.ack = 1;
        ev.stretch = 0;
        case (ev.ev)
            I2C_EV_ADDR: begin
                if (!ev.restart) begin
                    crc = 8'h00; wcnt = 0; rcnt = 0; err_mask = 0; bad = 0;
                    cmd_valid = 0; wbuf.delete(); exp_len = 0;
                    rd_start = ev.rw;
                    ara = (ev.addr[6:0] == SMB_ARA_ADDR) && !ev.addr10;
                end
                crc = odve_smbus_crc8(crc, {ev.addr[6:0], ev.rw});
                rd_seg = ev.rw;
                if (ev.rw) begin
                    rsp.delete();
                    rcnt = 0;
                    if (ara) begin
                        rsp.push_back({addr, 1'b0});
                    end else if (!ev.restart || !cmd_valid) begin
                        bit ok;
                        bit [7:0] b = recv_byte(ok);
                        rsp_ok = ok;
                        rsp.push_back(b);
                    end else if (!rd_ok(cmd)) begin
                        flag(ERR_CMD);
                    end else begin
                        do_read(cmd, wbuf, rsp);
                    end
                end
            end
            I2C_EV_WRITE: begin
                nc = odve_smbus_crc8(crc, ev.data);
                if (wcnt == 0) begin
                    cmd  = ev.data;
                    kind = cmd_kind(ev.data);
                    if (kind == SMB_CMD_NONE) begin
                        ev.ack = 0;
                        flag(ERR_CMD);
                    end else begin
                        cmd_valid = 1;
                        exp_len = len_of(kind);
                    end
                end else begin
                    int unsigned j = wcnt - 1;
                    if (bad) begin
                        ev.ack = 0;
                    end else if (j == 0 && kind != SMB_CMD_SEND && !wr_ok(cmd)) begin
                        ev.ack = 0;
                        flag(ERR_CMD);
                    end else if (j == 0 && exp_len < 0) begin
                        if (ev.data > max_block()) begin
                            ev.ack = 0;
                            flag(ERR_DATA);
                        end else begin
                            exp_len = 1 + ev.data;
                            wbuf.push_back(ev.data);
                        end
                    end else if (exp_len < 0 || int'(j) < exp_len) begin
                        wbuf.push_back(ev.data);
                    end else if (int'(j) == exp_len) begin
                        if (nc != 8'h00) begin
                            ev.ack = 0;
                            flag(ERR_PEC);
                        end
                    end else begin
                        ev.ack = 0;
                        flag(ERR_DATA);
                    end
                end
                crc = nc;
                wcnt++;
            end
            I2C_EV_READ: begin
                if (ev.idx < rsp.size())       ev.data = rsp[ev.idx];
                else if (ev.idx == rsp.size()) ev.data = bad_rd_pec ? ~crc : crc;
                else begin
                    ev.data = 8'hFF;
                    err_mask |= (1 << ERR_OTHER);
                end
                crc = odve_smbus_crc8(crc, ev.data);
                rcnt++;
            end
            default: begin   // STOP
                if (ev.tmo) begin
                    err_mask |= (1 << ERR_TMO);
                end else if (ev.abort) begin
                    err_mask |= (1 << ERR_OTHER);
                end else if (ara) begin
                    if (ev.nrd >= 1) alert = 0;
                end else if (rd_start) begin
                    if (ev.nrd == 0) quick(1);
                    else if (!rsp_ok) err_mask |= (1 << ERR_OTHER);
                end else if (!rd_seg) begin
                    if (wcnt == 0) quick(0);
                    else if (!bad && cmd_valid && exp_len >= 0 && (wcnt - 1 == exp_len || wcnt - 1 == exp_len + 1))
                        do_write(cmd, wbuf);
                end
                for (int c = 1; c <= ERR_TMO; c++) if (err_mask & (1 << c)) error(c);
                err_mask = 0;
            end
        endcase
    endfunction
endclass

// The SMBus device of this agent's TB - the same as the RTL in vrf/dut:
//   00h-07h  byte registers (Write/Read Byte)
//   10h-13h  word registers (Write/Read Word)
//   20h      Process Call: returns the written word inverted
//   30h      block register, up to 32 bytes (Block Write/Read)
//   31h      Block Write-Block Read Process Call: returns the written bytes inverted
//   40h      Send Byte CLEAR_STATUS: clears STATUS[4:0] and SMBALERT#
//   41h      Send Byte SET_ALERT: sets STATUS[2] and asserts SMBALERT#
//   Receive Byte: STATUS = {READY=1, 00, TMO, QUICK, ALERT_REQ, CMD_ERR, PEC_ERR}
//   Quick Command: STATUS.QUICK = the R/W# bit
//   Errors: unsupported/invalid -> CMD_ERR, bad PEC -> PEC_ERR, both assert
//   SMBALERT#; a clock-low timeout -> TMO.
class odve_smbus_ref_model extends odve_smbus_dev_model;
    `uvm_object_utils(odve_smbus_ref_model)

    bit [7:0]  bregs[8];
    bit [15:0] wregs[4];
    bit [7:0]  blk[$];
    bit        st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err;

    function new(string name = "odve_smbus_ref_model");
        super.new(name);
        foreach (bregs[i]) bregs[i] = 8'h00;
        foreach (wregs[i]) wregs[i] = 16'h0000;
    endfunction

    function bit [7:0] status();
        return {1'b1, 2'b00, st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err};
    endfunction

    virtual function odve_smbus_cmd_e cmd_kind(bit [7:0] c);
        if (c <= 8'h07)                  return SMB_CMD_BYTE;
        if (c >= 8'h10 && c <= 8'h13)    return SMB_CMD_WORD;
        if (c == 8'h20)                  return SMB_CMD_PCALL;
        if (c == 8'h30)                  return SMB_CMD_BLOCK;
        if (c == 8'h31)                  return SMB_CMD_BPCALL;
        if (c == 8'h40 || c == 8'h41)    return SMB_CMD_SEND;
        return SMB_CMD_NONE;
    endfunction

    virtual function bit rd_ok(bit [7:0] c);
        return cmd_kind(c) != SMB_CMD_SEND;
    endfunction

    virtual function void do_write(bit [7:0] c, bit [7:0] d[$]);
        case (cmd_kind(c))
            SMB_CMD_BYTE:  bregs[c[2:0]] = d[0];
            SMB_CMD_WORD:  wregs[c[1:0]] = {d[1], d[0]};
            SMB_CMD_BLOCK: begin
                blk.delete();
                for (int i = 1; i < d.size(); i++) blk.push_back(d[i]);
            end
            SMB_CMD_SEND: begin
                if (c == 8'h40) begin
                    {st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err} = '0;
                    alert = 0;
                end else begin
                    st_alert_req = 1;
                    alert = 1;
                end
            end
            default: ;   // process calls written without the read part: nothing to do
        endcase
    endfunction

    virtual function void do_read(bit [7:0] c, bit [7:0] w[$], ref bit [7:0] r[$]);
        case (cmd_kind(c))
            SMB_CMD_BYTE: r.push_back(bregs[c[2:0]]);
            SMB_CMD_WORD: begin
                r.push_back(wregs[c[1:0]][7:0]);
                r.push_back(wregs[c[1:0]][15:8]);
            end
            SMB_CMD_PCALL: begin
                r.push_back(~((w.size() > 0) ? w[0] : 8'h00));
                r.push_back(~((w.size() > 1) ? w[1] : 8'h00));
            end
            SMB_CMD_BLOCK: begin
                r.push_back(8'(blk.size()));
                foreach (blk[i]) r.push_back(blk[i]);
            end
            SMB_CMD_BPCALL: begin
                int unsigned m = (w.size() > 0) ? w.size() - 1 : 0;
                r.push_back(8'(m));
                for (int i = 1; i <= m; i++) r.push_back(~w[i]);
            end
            default: ;
        endcase
    endfunction

    virtual function bit [7:0] recv_byte(output bit ok);
        ok = 1;
        return status();
    endfunction

    virtual function void quick(bit rw);
        st_quick = rw;
    endfunction

    virtual function void error(int code);
        case (code)
            ERR_CMD, ERR_DATA: begin st_cmd_err = 1; alert = 1; end
            ERR_PEC:           begin st_pec_err = 1; alert = 1; end
            ERR_TMO:           st_tmo = 1;
            default: ;
        endcase
    endfunction
endclass
