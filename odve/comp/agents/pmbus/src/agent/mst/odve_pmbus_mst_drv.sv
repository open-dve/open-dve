// PMBus host (master role): each odve_pmbus_item becomes the SMBus message
// of its command's transaction type (Part II Table 31) - or item.force_proto
// - and runs on the smbus agent's sequencer (smb_sqr, set by the agent).
// Results and the decoded value go back into the item.
class odve_pmbus_mst_drv extends uvm_driver #(odve_pmbus_item);
    `uvm_component_utils(odve_pmbus_mst_drv)

    odve_pmbus_cfg cfg;
    odve_smbus_sqr smb_sqr;
    int unsigned   n_items = 0;

    function new(string name = "odve_pmbus_mst_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function odve_smbus_proto_e proto_of(odve_pmbus_item p);
        odve_smbus_cmd_e k = odve_pmbus_cmd_kind(p.cmd);
        if (p.force_proto != SMB_UNKNOWN) return p.force_proto;
        case (p.op)
            PMB_SEND:  return SMB_SEND_BYTE;
            PMB_WRITE: return (k == SMB_CMD_WORD) ? SMB_WRITE_WORD : (k == SMB_CMD_BLOCK) ? SMB_BLOCK_WRITE :
                              (k == SMB_CMD_NONE && p.wdata.size() == 2) ? SMB_WRITE_WORD : SMB_WRITE_BYTE;
            default:   return (k == SMB_CMD_WORD) ? SMB_READ_WORD : (k == SMB_CMD_BLOCK) ? SMB_BLOCK_READ : SMB_READ_BYTE;
        endcase
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_smbus_item_seq s;
        odve_smbus_item     m;
        forever begin
            seq_item_port.get_next_item(req);
            m = odve_smbus_item::type_id::create("m");
            m.proto   = proto_of(req);
            m.addr    = req.addr;
            m.cmd     = req.cmd;
            m.wdata   = req.wdata;
            m.pec     = req.pec;
            m.bad_pec = req.bad_pec;
            s = odve_smbus_item_seq::type_id::create("s");
            s.item = m;
            s.start(smb_sqr);
            req.proto       = m.proto;
            req.ack         = m.ack;
            req.nack_byte   = m.nack_byte;
            req.rdata       = m.rdata;
            req.pec_present = m.pec_present;
            req.pec_ok      = m.pec_ok;
            if (req.rdata.size() == 1 && req.cmd == PMB_VOUT_MODE && req.rdata[0][7:5] == 3'b000) cfg.vout_exp = req.rdata[0][4:0];
            req.value = odve_pmbus_value(req.cmd, (req.op == PMB_WRITE) ? req.wdata : req.rdata, cfg.vout_exp);
            n_items++;
            `uvm_info(get_name(), req.convert2string(), UVM_HIGH)
            seq_item_port.item_done();
        end
    endtask
endclass
