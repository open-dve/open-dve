// A PMBus device as an SMBus device model (odve_smbus_dev_model hooks) -
// the behaviour of the RTL in vrf/dut, PMBus 1.3.1 Part II:
//   pages 0 and 1 (PAGE 11.10; other values are invalid data, FFh included)
//   per page: OPERATION (12.1; accepted: bits [5:4] = 00 and [1:0] = 00,
//   anything else - margining, AVSBus, reserved - is invalid data),
//   ON_OFF_CONFIG (12.2; bits [7:5] must be 0), VOUT_COMMAND (ULINEAR16)
//   output on = !OOC[4] || (!OOC[3] || OPERATION[7]) (CONTROL pin taken as asserted)
//   VOUT_MODE 17h read only (ULINEAR16, exponent -9; a write is invalid data, 8.3.1)
//   READ_VOUT = VOUT_COMMAND when on, else 0; READ_IOUT LINEAR11 2.5 A /
//   1.25 A (page 0 / 1) when on, else 0 A; CAPABILITY 90h (PEC, 100 kHz,
//   SMBALERT#); PMBUS_REVISION 33h (Part I 1.3, Part II 1.3)
//   STATUS_BYTE {BUSY=0, OFF, 0000, CML, 0}; STATUS_WORD high byte bit 3
//   PG_STATUS# = OFF; both read only here
//   STATUS_CML (17.7): bit 7 invalid/unsupported command, 6 invalid data,
//   5 PEC failed, 1 other; written bits are cleared (10.2.4)
//   CLEAR_FAULTS (15.1) clears STATUS_CML and releases SMBALERT#
//   every communication fault sets its STATUS_CML bit and SMBALERT#
//   (10.8, 10.9); a message starting with a read (Receive Byte / Quick
//   Command read) is the 10.9.1 fault (FFh is sent, CML other)
class odve_pmbus_dev_model extends odve_smbus_dev_model;
    `uvm_object_utils(odve_pmbus_dev_model)

    int unsigned npages = 2;
    bit [7:0]    page = 0;
    bit [7:0]    operation[2];
    bit [7:0]    on_off_config[2];
    bit [15:0]   vout_command[2];
    bit [7:0]    cml = 0;

    localparam bit [7:0] VOUT_MODE_VAL = 8'h17, CAPABILITY_VAL = 8'h90, REVISION_VAL = 8'h33;

    function new(string name = "odve_pmbus_dev_model");
        super.new(name);
        foreach (operation[i])     operation[i]     = 8'h00;
        foreach (on_off_config[i]) on_off_config[i] = 8'h18;
        vout_command[0] = 16'h0200;      // 1.0 V
        vout_command[1] = 16'h0333;      // 1.6 V
    endfunction

    function bit is_on(int p);
        return !on_off_config[p][4] || (!on_off_config[p][3] || operation[p][7]);
    endfunction

    function bit [7:0] status_byte(int p);
        return {1'b0, !is_on(p), 4'b0000, (cml != 8'h00), 1'b0};
    endfunction

    function bit [15:0] iout(int p);
        if (!is_on(p)) return 16'hF000;
        return (p == 0) ? 16'hF00A : 16'hF005;    // 10 * 2^-2 = 2.5 A, 5 * 2^-2 = 1.25 A
    endfunction

    function void fault(int bitn);
        cml[bitn] = 1;
        alert = 1;
    endfunction

    virtual function odve_smbus_cmd_e cmd_kind(bit [7:0] c);
        if (c inside {PMB_PAGE, PMB_OPERATION, PMB_ON_OFF_CONFIG, PMB_CLEAR_FAULTS, PMB_CAPABILITY, PMB_VOUT_MODE,
                      PMB_VOUT_COMMAND, PMB_STATUS_BYTE, PMB_STATUS_WORD, PMB_STATUS_CML, PMB_READ_VOUT,
                      PMB_READ_IOUT, PMB_PMBUS_REVISION})
            return odve_pmbus_cmd_kind(c);
        return SMB_CMD_NONE;
    endfunction

    virtual function bit wr_ok(bit [7:0] c);
        return !(c inside {PMB_CAPABILITY, PMB_READ_VOUT, PMB_READ_IOUT, PMB_PMBUS_REVISION, PMB_STATUS_BYTE, PMB_STATUS_WORD});
    endfunction

    virtual function bit rd_ok(bit [7:0] c);
        return cmd_kind(c) != SMB_CMD_SEND;
    endfunction

    virtual function void do_write(bit [7:0] c, bit [7:0] d[$]);
        case (c)
            PMB_PAGE:          if (d[0] < npages) page = d[0]; else fault(PMB_CML_DATA);
            PMB_OPERATION:     if (d[0][5:4] == 2'b00 && d[0][1:0] == 2'b00) operation[page] = d[0]; else fault(PMB_CML_DATA);
            PMB_ON_OFF_CONFIG: if (d[0][7:5] == 3'b000) on_off_config[page] = d[0]; else fault(PMB_CML_DATA);
            PMB_VOUT_MODE:     fault(PMB_CML_DATA);
            PMB_VOUT_COMMAND:  vout_command[page] = {d[1], d[0]};
            PMB_STATUS_CML:    cml = cml & ~d[0];
            PMB_CLEAR_FAULTS:  begin cml = 8'h00; alert = 0; end
            default: ;
        endcase
    endfunction

    virtual function void do_read(bit [7:0] c, bit [7:0] w[$], ref bit [7:0] r[$]);
        bit [15:0] v;
        case (c)
            PMB_PAGE:           r.push_back(page);
            PMB_OPERATION:      r.push_back(operation[page]);
            PMB_ON_OFF_CONFIG:  r.push_back(on_off_config[page]);
            PMB_CAPABILITY:     r.push_back(CAPABILITY_VAL);
            PMB_VOUT_MODE:      r.push_back(VOUT_MODE_VAL);
            PMB_STATUS_BYTE:    r.push_back(status_byte(page));
            PMB_STATUS_CML:     r.push_back(cml);
            PMB_PMBUS_REVISION: r.push_back(REVISION_VAL);
            default: begin
                case (c)
                    PMB_VOUT_COMMAND: v = vout_command[page];
                    PMB_STATUS_WORD:  v = {4'b0000, !is_on(page), 3'b000, status_byte(page)};
                    PMB_READ_VOUT:    v = is_on(page) ? vout_command[page] : 16'h0000;
                    PMB_READ_IOUT:    v = iout(page);
                    default:          v = 16'hFFFF;
                endcase
                r.push_back(v[7:0]);
                r.push_back(v[15:8]);
            end
        endcase
    endfunction

    virtual function bit [7:0] recv_byte(output bit ok);
        ok = 0;              // 10.9.1: ACK, send FFh, CML other
        return 8'hFF;
    endfunction

    virtual function void quick(bit rw);
        if (rw) fault(PMB_CML_OTHER);
    endfunction

    virtual function void error(int code);
        case (code)
            ERR_CMD:  fault(PMB_CML_CMD);
            ERR_DATA: fault(PMB_CML_DATA);
            ERR_PEC:  fault(PMB_CML_PEC);
            default:  fault(PMB_CML_OTHER);    // too few bits, reading too many bytes, read at start, clock-low timeout
        endcase
    endfunction
endclass
