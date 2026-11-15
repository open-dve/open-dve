// Reference model of the PMBus device (from its definition in vrf/dut/dut.sv
// and PMBus 1.3.1 Part II 10.8/10.9, independent of odve_pmbus_dev_model),
// checked against every message the host's PMBus monitor reports. It
// replays the raw bytes of each message through its own rules:
//   * address ACK; ARA only while SMBALERT# is expected
//   * written bytes: unsupported code -> NACK of the code (CML bit 7); data
//     to a read-only code -> NACK (bit 7); after the full data one byte is
//     taken as PEC (NACK + bit 5 when wrong); any further byte NACKed (bit 6)
//   * complete, error-free writes take effect; invalid data (PAGE, OPERATION,
//     ON_OFF_CONFIG, VOUT_MODE) -> bit 6, nothing changes
//   * reads: every data byte against the model; reading past the PEC -> bit 1;
//     a read of a send-only code -> bit 7; a message starting with a read -> FFh, bit 1
//   * any CML bit asserts SMBALERT#; CLEAR_FAULTS and the ARA read release it
//   * SMBALERT# is compared at the end of every message
`uvm_analysis_imp_decl(_pmbus)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_pmbus #(odve_pmbus_item, scb) pmbus_imp;

    bit [7:0]  page = 0, cml = 0;
    bit [7:0]  operation[2], ooc[2];
    bit [15:0] vout[2];
    bit        alert = 0;
    int unsigned n_msg = 0, n_rd = 0, n_wr = 0, n_fault = 0, n_err = 0;

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        pmbus_imp = new("pmbus_imp", this);
        operation = '{8'h00, 8'h00};
        ooc       = '{8'h18, 8'h18};
        vout      = '{16'h0200, 16'h0333};
    endfunction

    function void err(odve_pmbus_item p, string msg);
        n_err++;
        `uvm_error(get_name(), $sformatf("%s: %s", p.convert2string(), msg))
    endfunction

    function void fault(int b);
        cml[b] = 1;
        n_fault++;
    endfunction

    function bit supported(bit [7:0] c);
        return c inside {8'h00, 8'h01, 8'h02, 8'h03, 8'h19, 8'h20, 8'h21, 8'h78, 8'h79, 8'h7E, 8'h8B, 8'h8C, 8'h98};
    endfunction

    function int dlen(bit [7:0] c);      // data bytes of the command
        if (c == 8'h03) return 0;
        if (c inside {8'h21, 8'h79, 8'h8B, 8'h8C}) return 2;
        return 1;
    endfunction

    function bit on_p();
        return !ooc[page][4] || !ooc[page][3] || operation[page][7];
    endfunction

    function bit [15:0] value_of(bit [7:0] c);
        bit [7:0] sb = {1'b0, !on_p(), 4'b0000, cml != 8'h00, 1'b0};
        case (c)
            8'h00: return {8'h00, page};
            8'h01: return {8'h00, operation[page]};
            8'h02: return {8'h00, ooc[page]};
            8'h19: return 16'h0090;
            8'h20: return 16'h0017;
            8'h21: return vout[page];
            8'h78: return {8'h00, sb};
            8'h79: return {4'b0000, !on_p(), 3'b000, sb};
            8'h7E: return {8'h00, cml};
            8'h8B: return on_p() ? vout[page] : 16'h0000;
            8'h8C: return !on_p() ? 16'hF000 : (page == 0) ? 16'hF00A : 16'hF005;
            8'h98: return 16'h0033;
            default: return 16'hFFFF;
        endcase
    endfunction

    function void commit(bit [7:0] c, bit [7:0] d[$]);
        n_wr++;
        case (c)
            8'h00: if (d[0] < 2) page = d[0]; else fault(6);
            8'h01: if (d[0][5:4] == 2'b00 && d[0][1:0] == 2'b00) operation[page] = d[0]; else fault(6);
            8'h02: if (d[0][7:5] == 3'b000) ooc[page] = d[0]; else fault(6);
            8'h20: fault(6);
            8'h21: vout[page] = {d[1], d[0]};
            8'h7E: cml = cml & ~d[0];
            8'h03: begin cml = 8'h00; alert = 0; end
            default: ;
        endcase
    endfunction

    function void write_pmbus(odve_pmbus_item p);
        bit [7:0] c, crc, msg[$], d[$];
        int exp_nack, ndat;
        bit [15:0] v;
        int unsigned f0 = n_fault;
        n_msg++;
        if (p.alert != alert) err(p, $sformatf("SMBALERT# %s, expected %s", p.alert ? "asserted" : "released", alert ? "asserted" : "released"));

        if (p.proto == SMB_ARA) begin
            if (p.ack != alert) err(p, $sformatf("ARA %s while SMBALERT# is %s", p.ack ? "ACKed" : "NACKed", alert ? "expected" : "not expected"));
            if (p.ack && (p.raw_rd.size() == 0 || p.raw_rd[0] != {DEV_ADDR, 1'b0})) err(p, "ARA did not return the device address");
            if (p.raw_rd.size() > 2) fault(1);
            if (p.ack && p.raw_rd.size() >= 1) alert = 0;
            if (cml != 8'h00 && p.raw_rd.size() > 2) alert = 1;
            return;
        end
        if (p.addr != DEV_ADDR) begin
            if (p.ack) err(p, "an absent address was ACKed");
            return;
        end
        if (p.nack_byte == 0) begin
            err(p, "the device's address was NACKed");
            return;
        end

        // message starting with a read (Part II 10.9.1)
        if (p.proto inside {SMB_RECV_BYTE, SMB_QUICK_R}) begin
            if (p.raw_rd.size() > 0 && p.raw_rd[0] != 8'hFF) err(p, $sformatf("read at START answered 0x%02h, expected FFh", p.raw_rd[0]));
            fault(1);
            alert = 1;
            return;
        end
        if (p.raw_wr.size() == 0) return;     // Quick Command write: nothing

        // the write part, byte by byte
        c = p.raw_wr[0];
        exp_nack = -1;
        msg.push_back({DEV_ADDR, 1'b0});
        msg.push_back(c);
        if (!supported(c)) begin
            exp_nack = 1;
            fault(7);
        end else begin
            for (int j = 0; j + 1 < p.raw_wr.size(); j++) begin
                bit [7:0] b = p.raw_wr[j + 1];
                msg.push_back(b);
                if (j == 0 && c != 8'h03 && c inside {8'h19, 8'h78, 8'h79, 8'h8B, 8'h8C, 8'h98}) begin
                    exp_nack = 2 + j; fault(7); break;
                end else if (j < dlen(c)) begin
                    d.push_back(b);
                end else if (j == dlen(c)) begin
                    if (odve_smbus_pec(msg) != 8'h00) begin exp_nack = 2 + j; fault(5); break; end
                end else begin
                    exp_nack = 2 + j; fault(6); break;
                end
            end
        end
        if (p.nack_byte != exp_nack) err(p, $sformatf("first NACK at byte %0d, expected %0d", p.nack_byte, exp_nack));

        if (exp_nack < 0 && supported(c)) begin
            if (p.raw_rd.size() == 0 && p.proto != SMB_UNKNOWN) begin
                // a write message: carried out when complete
                if (d.size() == dlen(c)) commit(c, d);
            end else if (p.proto != SMB_UNKNOWN || p.raw_rd.size() > 0) begin
                // a read of the command
                if (c == 8'h03) begin
                    fault(7);
                end else begin
                    ndat = dlen(c);
                    v = value_of(c);
                    n_rd++;
                    for (int i = 0; i < ndat && i < p.raw_rd.size(); i++)
                        if (p.raw_rd[i] !== v[8*i +: 8]) err(p, $sformatf("read byte %0d = 0x%02h, expected 0x%02h", i, p.raw_rd[i], v[8*i +: 8]));
                    if (p.raw_rd.size() > ndat + 1) fault(1);     // past the PEC (10.8.6)
                end
            end
        end
        if (n_fault != f0) alert = 1;     // every communication fault notifies the host
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d messages checked: %0d reads, %0d writes, %0d faults, %0d errors", n_msg, n_rd, n_wr, n_fault, n_err), UVM_LOW)
        if (n_msg == 0) `uvm_error(get_name(), "no PMBus messages observed")
    endfunction
endclass : scb
