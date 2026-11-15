// One PMBus command (Part II): op + command code + data, sent with the
// SMBus protocol of the command's transaction type (Table 31): Write Byte /
// Write Word / Block Write (PMB_WRITE), Read Byte / Read Word / Block Read
// (PMB_READ), Send Byte (PMB_SEND). Data bytes low byte first.
class odve_pmbus_item extends uvm_sequence_item;
    `uvm_object_utils(odve_pmbus_item)

    // ---- request ----------------------------------------------------------
    odve_pmbus_op_e    op    = PMB_READ;
    bit [7:0]          cmd   = PMB_PMBUS_REVISION;
    bit [7:0]          wdata[$];             // PMB_WRITE: the data bytes
    bit                pec   = 0;
    bit [6:0]          addr  = 7'h40;
    // error injection: another SMBus protocol than the command's (SMB_UNKNOWN = the command's own), a wrong PEC
    odve_smbus_proto_e force_proto = SMB_UNKNOWN;
    bit                bad_pec = 0;

    // ---- response / observation --------------------------------------------
    bit [7:0]          rdata[$];             // PMB_READ: the data bytes
    bit                ack     = 0;
    int                nack_byte = -1;
    bit                pec_present = 0, pec_ok = 1;
    bit                complete = 0;
    int                page    = 0;          // monitor: the PAGE in effect
    real               value   = 0.0;        // monitor/host: the decoded value (LINEAR11 / ULINEAR16)
    bit                alert   = 0;          // monitor: SMBALERT# low at the end
    odve_smbus_proto_e proto   = SMB_UNKNOWN;// the SMBus protocol used
    bit [7:0]          raw_wr[$], raw_rd[$]; // monitor: the bytes on the bus after the address (see odve_smbus_item)

    // ---- knobs of user_randomize() -----------------------------------------
    odve_rand          rng;
    bit [7:0]          cmds[$];              // codes to draw from (default: the supported set of the TB device)
    int unsigned       p_pec     = 50;
    int unsigned       p_invalid = 0;        // % of commands with invalid data / unsupported codes

    function new(string name = "odve_pmbus_item");
        super.new(name);
    endfunction

    function int unsigned nbytes();
        case (odve_pmbus_cmd_kind(cmd))
            SMB_CMD_BYTE: return 1;
            SMB_CMD_WORD: return 2;
            default:      return 0;
        endcase
    endfunction

    // A random command of the list: read or write as the code allows,
    // random data (OPERATION / ON_OFF_CONFIG / PAGE mostly valid values).
    function void user_randomize();
        odve_smbus_cmd_e k;
        if (rng == null) rng = new("odve_pmbus_item");
        if (cmds.size() == 0)
            cmds = '{PMB_PAGE, PMB_OPERATION, PMB_ON_OFF_CONFIG, PMB_CLEAR_FAULTS, PMB_CAPABILITY, PMB_VOUT_MODE,
                     PMB_VOUT_COMMAND, PMB_STATUS_BYTE, PMB_STATUS_WORD, PMB_STATUS_CML, PMB_READ_VOUT,
                     PMB_READ_IOUT, PMB_PMBUS_REVISION};
        cmd = cmds[rng.index(cmds.size())];
        if (rng.chance(p_invalid)) cmd = 8'hD0 + 8'(rng.urand(0, 15));      // a manufacturer-specific code the device lacks
        k = odve_pmbus_cmd_kind(cmd);
        pec = rng.chance(p_pec);
        wdata.delete();
        rdata.delete();
        if (k == SMB_CMD_SEND) op = PMB_SEND;
        else if (odve_pmbus_read_only(cmd) || k == SMB_CMD_NONE || cmd inside {PMB_STATUS_BYTE, PMB_STATUS_WORD, PMB_VOUT_MODE}) op = PMB_READ;
        else op = rng.chance(50) ? PMB_WRITE : PMB_READ;
        if (k == SMB_CMD_NONE) begin
            op = rng.chance(50) ? PMB_WRITE : PMB_READ;
            if (op == PMB_WRITE) wdata.push_back(8'(rng.u16()));
            return;
        end
        if (op != PMB_WRITE) return;
        case (cmd)
            PMB_PAGE:          wdata.push_back(rng.chance(90) ? 8'(rng.urand(0, 1)) : 8'(rng.urand(2, 255)));
            PMB_OPERATION:     wdata.push_back(rng.chance(90) ? {rng.chance(50) ? 1'b1 : 1'b0, rng.chance(50) ? 1'b1 : 1'b0, 6'b00_10_00}
                                                              : 8'(rng.u16()));
            PMB_ON_OFF_CONFIG: wdata.push_back(rng.chance(90) ? {3'b000, 5'(rng.u16())} : 8'(rng.u16()));
            PMB_STATUS_CML:    wdata.push_back(8'(rng.u16()));
            default: begin
                bit [15:0] w = 16'(rng.urand(0, 16'h0C00));     // VOUT_COMMAND: 0 .. 6 V at 2^-9
                wdata.push_back(w[7:0]);
                if (nbytes() == 2) wdata.push_back(w[15:8]);
            end
        endcase
    endfunction

    function string convert2string();
        string s = $sformatf("%s %s(%02h) page=%0d", op == PMB_WRITE ? "WR" : op == PMB_SEND ? "SEND" : "RD", odve_pmbus_cmd_name(cmd), cmd, page);
        if (wdata.size() > 0) begin
            s = {s, " w:"};
            foreach (wdata[i]) s = {s, $sformatf(" %02h", wdata[i])};
        end
        if (rdata.size() > 0) begin
            s = {s, " r:"};
            foreach (rdata[i]) s = {s, $sformatf(" %02h", rdata[i])};
        end
        if (odve_pmbus_fmt(cmd) != PMB_FMT_RAW && (wdata.size() == 2 || rdata.size() == 2)) s = {s, $sformatf(" (%0.4f)", value)};
        if (pec_present) s = {s, pec_ok ? " PEC" : " PEC(BAD)"};
        if (!ack)  s = {s, $sformatf(" NACK@%0d", nack_byte)};
        if (alert) s = {s, " ALERT"};
        return s;
    endfunction
endclass
