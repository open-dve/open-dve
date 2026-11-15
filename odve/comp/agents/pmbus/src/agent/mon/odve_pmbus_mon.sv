// PMBus monitor: turns every SMBus message the smbus monitor decodes (via
// smb_imp) into an odve_pmbus_item - command name, op, the PAGE in effect
// (tracked from accepted PAGE writes), the value in its data format
// (LINEAR11, ULINEAR16 with the VOUT_MODE exponent, tracked from VOUT_MODE
// reads) - and publishes it on item_collected_port.
//
// Checks (uvm_error, id PMB_PROTO; tests that provoke them demote the id):
//   * a message to a device starting with a read (Part II 10.9.1; the
//     Alert Response Address is the exception)
//   * a command sent with another SMBus protocol than its Table 31
//     transaction type
class odve_pmbus_mon extends uvm_monitor;
    `uvm_component_utils(odve_pmbus_mon)

    uvm_analysis_imp #(odve_smbus_item, odve_pmbus_mon) smb_imp;
    uvm_analysis_port #(odve_pmbus_item) item_collected_port;

    odve_pmbus_cfg cfg;
    int unsigned   page = 0;
    int unsigned   n_seen = 0, n_proto_err = 0;

    `odve_cov_create(odve_pmbus_cg)

    function new(string name = "odve_pmbus_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        smb_imp = new("smb_imp", this);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void proto_err(string msg);
        n_proto_err++;
        `uvm_error("PMB_PROTO", msg)
    endfunction

    function void write(odve_smbus_item m);
        odve_pmbus_item p;
        odve_smbus_cmd_e k;
        bit proto_ok;
        p = odve_pmbus_item::type_id::create("p");
        p.raw_wr = m.raw_wr;
        p.raw_rd = m.raw_rd;
        p.addr  = m.addr;
        p.cmd   = m.cmd;
        p.proto = m.proto;
        p.pec   = m.pec_present;
        p.pec_present = m.pec_present;
        p.pec_ok = m.pec_ok;
        p.ack   = m.ack;
        p.nack_byte = m.nack_byte;
        p.complete = m.complete;
        p.alert = m.alert;
        p.page  = page;
        p.wdata = m.wdata;
        p.rdata = m.rdata;
        // send / read / write, from the bytes on the bus (an unsupported code is still a write or a read)
        if (m.proto == SMB_SEND_BYTE)                                       p.op = PMB_SEND;
        else if (m.raw_rd.size() > 0 || m.proto inside {SMB_RECV_BYTE, SMB_QUICK_R, SMB_READ_BYTE, SMB_READ_WORD, SMB_BLOCK_READ})
                                                                            p.op = PMB_READ;
        else                                                                p.op = PMB_WRITE;
        if (m.proto == SMB_SEND_BYTE) p.wdata.delete();
        if (m.proto == SMB_ARA) begin           // SMBus alert handling: passed on, not a PMBus command
            n_seen++;
            item_collected_port.write(p);
            return;
        end
        if (m.addr_ack && (m.proto == SMB_RECV_BYTE || m.proto == SMB_QUICK_R))
            proto_err($sformatf("message to 0x%02h starts with a read (Part II 10.9.1): %s", m.addr, m.convert2string()));
        k = odve_pmbus_cmd_kind(m.cmd);
        if (k != SMB_CMD_NONE && m.addr_ack && !(m.proto inside {SMB_RECV_BYTE, SMB_QUICK_R, SMB_QUICK_W})) begin
            case (k)
                SMB_CMD_SEND:  proto_ok = m.proto == SMB_SEND_BYTE;
                SMB_CMD_BYTE:  proto_ok = m.proto inside {SMB_WRITE_BYTE, SMB_READ_BYTE};
                SMB_CMD_WORD:  proto_ok = m.proto inside {SMB_WRITE_WORD, SMB_READ_WORD};
                SMB_CMD_BLOCK: proto_ok = m.proto inside {SMB_BLOCK_WRITE, SMB_BLOCK_READ};
                default:       proto_ok = 1;
            endcase
            if (!proto_ok) proto_err($sformatf("%s sent as %s: %s", odve_pmbus_cmd_name(m.cmd), odve_smbus_proto_str(m.proto), m.convert2string()));
        end
        // context: PAGE, VOUT_MODE
        if (m.proto == SMB_WRITE_BYTE && m.cmd == PMB_PAGE && m.ack && m.complete && m.wdata[0] < cfg.npages && (!m.pec_present || m.pec_ok))
            page = m.wdata[0];
        if (m.proto == SMB_READ_BYTE && m.cmd == PMB_VOUT_MODE && m.rdata.size() == 1 && m.rdata[0][7:5] == 3'b000)
            cfg.vout_exp = m.rdata[0][4:0];
        p.value = odve_pmbus_value(p.cmd, (p.op == PMB_WRITE) ? p.wdata : p.rdata, cfg.vout_exp);
        n_seen++;
        `uvm_info(get_name(), p.convert2string(), UVM_HIGH)
        `odve_cov_sample(odve_pmbus_cg, int'(p.cmd), int'(p.op), p.page, p.pec_present, p.ack, p.alert, (p.cmd == PMB_STATUS_CML && p.rdata.size() == 1) ? int'(p.rdata[0]) : -1, value_bin(p))
        item_collected_port.write(p);
    endfunction

    // coarse value classes for coverage: -1 none, 0 zero, 1 below 1, 2 1..2, 3 above 2
    function int value_bin(odve_pmbus_item p);
        if (odve_pmbus_fmt(p.cmd) == PMB_FMT_RAW || (p.wdata.size() != 2 && p.rdata.size() != 2)) return -1;
        if (p.value == 0.0) return 0;
        if (p.value < 1.0)  return 1;
        if (p.value <= 2.0) return 2;
        return 3;
    endfunction
endclass
