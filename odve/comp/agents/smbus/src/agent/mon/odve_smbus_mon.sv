// SMBus monitor: decodes every I2C transfer the i2c monitor reports (via
// i2c_imp) into the SMBus protocol it carries, using cfg.cmd_tab (what each
// command code of the device means), checks the PEC when one is present and
// publishes an odve_smbus_item on item_collected_port.
//
// Checks (uvm_error; tests that provoke them demote the id and count):
//   SMB_PEC      a PEC byte that does not match the message (6.4)
//   SMB_TIMEOUT  a target still pulls SMBCLK/SMBDAT low after SMBCLK has
//                been low for tTIMEOUT,MAX (4.2.2: it must have reset)
//   SMB_SEXT     a target stretched the clock for more than tLOW:SEXT in
//                one message (4.2.4)
// Informational: messages ended before the protocol's length (n_short),
// messages with SCL low >= tTIMEOUT,MIN (item.timeout, n_timeout).
class odve_smbus_mon extends uvm_monitor;
    `uvm_component_utils(odve_smbus_mon)

    uvm_analysis_imp #(odve_i2c_item, odve_smbus_mon) i2c_imp;
    uvm_analysis_port #(odve_smbus_item) item_collected_port;

    odve_smbus_cfg        cfg;
    virtual odve_smbus_if vif;

    int unsigned n_seen = 0, n_pec = 0, n_pec_err = 0, n_short = 0, n_timeout = 0, n_tmo_err = 0, n_sext_err = 0;

    `odve_cov_create(odve_smbus_cg)

    local int unsigned sext;     // target stretch cycles in the current message

    function new(string name = "odve_smbus_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        i2c_imp = new("i2c_imp", this);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function int len_of(odve_smbus_cmd_e k);
        case (k)
            SMB_CMD_SEND:  return 0;
            SMB_CMD_BYTE:  return 1;
            default:       return 2;
        endcase
    endfunction

    // n data bytes after the command, from index `from` of q
    function void take(ref bit [7:0] dst[$], input bit [7:0] q[$], input int from, input int n);
        dst.delete();
        for (int i = from; i < from + n && i < q.size(); i++) dst.push_back(q[i]);
    endfunction

    function void write(odve_i2c_item t);
        odve_smbus_item  m;
        odve_smbus_cmd_e k;
        bit [7:0] msg[$];
        int exp_w, exp_r, nr, nw;
        bit  pec_w;
        if (t.addr10) begin
            `uvm_warning(get_name(), {"10-bit transfer on an SMBus: ", t.convert2string()})
            return;
        end
        m = odve_smbus_item::type_id::create("m");
        m.addr      = t.addr[6:0];
        m.addr_ack  = t.addr_ack;
        m.ack       = t.addr_ack && !t.wr_nack;
        m.nack_byte = !t.addr_ack ? 0 : t.wr_nack ? t.wack.size() : -1;
        m.aborted   = t.aborted;
        m.timeout   = cfg.t_timeout_min != 0 && t.max_scl_low >= cfg.t_timeout_min;
        m.alert     = (vif != null && vif.alert_n === 1'b0);
        m.nbytes    = 1 + t.wdata.size() + t.rdata.size() + ((t.kind == I2C_WRITE_READ) ? 1 : 0);
        m.cmd       = (t.wdata.size() > 0) ? t.wdata[0] : 8'h00;
        m.raw_wr    = t.wdata;
        m.raw_rd    = t.rdata;
        k           = cmd_tab_of(m.cmd);
        nw          = t.wdata.size();
        nr          = t.rdata.size();
        exp_w       = -1;
        exp_r       = -1;

        // the whole message, for the PEC
        if (t.kind != I2C_READ) begin
            msg.push_back({m.addr, 1'b0});
            foreach (t.wdata[i]) msg.push_back(t.wdata[i]);
        end
        if (t.kind != I2C_WRITE) begin
            msg.push_back({m.addr, 1'b1});
            foreach (t.rdata[i]) msg.push_back(t.rdata[i]);
        end

        case (t.kind)
            I2C_WRITE: begin
                if (nw == 0) begin
                    m.proto = SMB_QUICK_W;
                    exp_w = 0;
                end else begin
                    case (k)
                        SMB_CMD_SEND:  m.proto = SMB_SEND_BYTE;
                        SMB_CMD_BYTE:  m.proto = SMB_WRITE_BYTE;
                        SMB_CMD_WORD:  m.proto = SMB_WRITE_WORD;
                        SMB_CMD_PCALL: m.proto = SMB_PROC_CALL;        // without its read part
                        SMB_CMD_BLOCK, SMB_CMD_BPCALL: m.proto = (k == SMB_CMD_BLOCK) ? SMB_BLOCK_WRITE : SMB_BLOCK_PROC_CALL;
                        default:       m.proto = SMB_UNKNOWN;
                    endcase
                    if (k inside {SMB_CMD_BLOCK, SMB_CMD_BPCALL}) begin
                        if (nw >= 2) m.wcount = t.wdata[1];
                        if (nw >= 2) exp_w = 2 + t.wdata[1];
                        if (nw >= 2) take(m.wdata, t.wdata, 2, t.wdata[1]);
                    end else if (k != SMB_CMD_NONE) begin
                        exp_w = 1 + len_of(k);
                        take(m.wdata, t.wdata, 1, len_of(k));
                    end
                    if (k inside {SMB_CMD_PCALL, SMB_CMD_BPCALL}) exp_w = -1;   // a process call needs its read part
                    pec_w = exp_w >= 0 && nw == exp_w + 1;
                    if (pec_w) begin
                        m.pec_present = 1;
                        m.pec_rx = t.wdata[nw - 1];
                    end
                    m.complete = exp_w >= 0 && (nw == exp_w || pec_w);
                end
                if (m.proto == SMB_QUICK_W) m.complete = 1;
            end
            I2C_READ: begin
                if (m.addr == SMB_ARA_ADDR) begin
                    m.proto = SMB_ARA;
                    exp_r = 1;
                end else if (nr == 0) begin
                    m.proto = SMB_QUICK_R;
                    exp_r = 0;
                end else begin
                    m.proto = SMB_RECV_BYTE;
                    exp_r = 1;
                end
                take(m.rdata, t.rdata, 0, exp_r);
            end
            default: begin   // write, Sr, read
                case (k)
                    SMB_CMD_BYTE:   begin m.proto = SMB_READ_BYTE; exp_w = 1; exp_r = 1; end
                    SMB_CMD_WORD:   begin m.proto = SMB_READ_WORD; exp_w = 1; exp_r = 2; end
                    SMB_CMD_PCALL:  begin m.proto = SMB_PROC_CALL; exp_w = 3; exp_r = 2; take(m.wdata, t.wdata, 1, 2); end
                    SMB_CMD_BLOCK:  begin m.proto = SMB_BLOCK_READ; exp_w = 1; end
                    SMB_CMD_BPCALL: begin
                        m.proto = SMB_BLOCK_PROC_CALL;
                        if (nw >= 2) begin
                            m.wcount = t.wdata[1];
                            exp_w = 2 + t.wdata[1];
                            take(m.wdata, t.wdata, 2, t.wdata[1]);
                        end
                    end
                    default:        m.proto = SMB_UNKNOWN;
                endcase
                if (k inside {SMB_CMD_BLOCK, SMB_CMD_BPCALL} && nr >= 1) begin
                    m.count = t.rdata[0];
                    exp_r = 1 + m.count;
                    take(m.rdata, t.rdata, 1, m.count);
                end else if (exp_r >= 0) begin
                    take(m.rdata, t.rdata, 0, exp_r);
                end
            end
        endcase
        if (t.kind != I2C_WRITE) begin
            if (exp_r >= 0 && nr == exp_r + 1) begin
                m.pec_present = 1;
                m.pec_rx = t.rdata[nr - 1];
            end
            m.complete = exp_r >= 0 && (nr == exp_r || nr == exp_r + 1) && (t.kind == I2C_READ || nw == exp_w);
        end
        if (m.pec_present) begin
            n_pec++;
            m.pec_ok = (odve_smbus_pec(msg) == 8'h00);    // the CRC over message + PEC is 0
            if (!m.pec_ok) begin
                n_pec_err++;
                `uvm_error("SMB_PEC", $sformatf("PEC mismatch: %s (expected 0x%02h)", m.convert2string(), odve_smbus_pec(msg[0:msg.size() - 2])))
            end
        end
        if (m.timeout) n_timeout++;
        if (!m.complete && m.ack && !m.timeout && !m.aborted) n_short++;
        n_seen++;
        `uvm_info(get_name(), m.convert2string(), UVM_HIGH)
        `odve_cov_sample(odve_smbus_cg, int'(m.proto), m.pec_present, m.pec_ok, m.ack, int'(m.count), m.timeout, m.alert, int'(m.wdata.size()))
        item_collected_port.write(m);
    endfunction

    function odve_smbus_cmd_e cmd_tab_of(bit [7:0] c);
        return cfg.cmd_tab[c];
    endfunction

    // bus-level timeout checks, on the transport's pins
    virtual task run_phase(uvm_phase phase);
        virtual odve_i2c_if b = cfg.i2c_vif;
        int unsigned low = 0;
        bit busy = 0, pscl = 1, psda = 1, scl, sda;
        forever begin
            @(posedge b.clk);
            scl = (b.scl === 1'b1);
            sda = (b.sda === 1'b1);
            if (scl && pscl && psda && !sda) begin busy = 1; sext = 0; end
            if (scl && pscl && !psda && sda) busy = 0;
            low = scl ? 0 : low + 1;
            if (busy && b.t_scl_pull === 1'b1) begin
                sext++;
                if (cfg.t_low_sext != 0 && sext == cfg.t_low_sext + 1) begin
                    n_sext_err++;
                    `uvm_error("SMB_SEXT", $sformatf("target clock stretching exceeds tLOW:SEXT (%0d cycles) in one message", cfg.t_low_sext))
                end
            end
            if (cfg.t_timeout_max != 0 && low == cfg.t_timeout_max + 1 && (b.t_scl_pull === 1'b1 || b.t_sda_pull === 1'b1)) begin
                n_tmo_err++;
                `uvm_error("SMB_TIMEOUT", $sformatf("SMBCLK low for %0d cycles (tTIMEOUT,MAX) and a target still pulls %s low", cfg.t_timeout_max, b.t_scl_pull === 1'b1 ? "SMBCLK" : "SMBDAT"))
            end
            pscl = scl;
            psda = sda;
        end
    endtask
endclass
