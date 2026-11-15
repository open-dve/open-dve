// SMBus host (master role): turns each odve_smbus_item into the I2C transfer
// of its protocol (SMBus 3.3 6.5) - command code, byte count, PEC appended
// on writes (computed over every byte from the address, 6.4), one more byte
// read for the PEC on reads - and runs it on the i2c agent's sequencer
// (layering; i2c_sqr is set by the agent). Results go back into the item:
// addr_ack, ack, nack_byte, rdata, count, pec_present/pec_rx/pec_ok.
class odve_smbus_mst_drv extends uvm_driver #(odve_smbus_item);
    `uvm_component_utils(odve_smbus_mst_drv)

    odve_smbus_cfg cfg;
    odve_i2c_sqr   i2c_sqr;
    int unsigned   n_items = 0;

    function new(string name = "odve_smbus_mst_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function odve_i2c_item to_i2c(odve_smbus_item m);
        odve_i2c_item t = odve_i2c_item::type_id::create("t");
        int unsigned p = m.pec ? 1 : 0;
        t.addr   = 10'(m.addr);
        t.addr10 = 0;
        t.wdata.delete();
        case (m.proto)
            SMB_QUICK_W:     t.kind = I2C_WRITE;
            SMB_QUICK_R:     begin t.kind = I2C_READ; t.nrd = 0; end
            SMB_SEND_BYTE:   begin t.kind = I2C_WRITE; t.wdata.push_back(m.cmd); end
            SMB_RECV_BYTE, SMB_ARA: begin t.kind = I2C_READ; t.nrd = 1 + p; end
            SMB_WRITE_BYTE, SMB_WRITE_WORD: begin
                t.kind = I2C_WRITE;
                t.wdata.push_back(m.cmd);
                foreach (m.wdata[i]) t.wdata.push_back(m.wdata[i]);
            end
            SMB_BLOCK_WRITE: begin
                t.kind = I2C_WRITE;
                t.wdata.push_back(m.cmd);
                t.wdata.push_back(8'(m.wdata.size()));
                foreach (m.wdata[i]) t.wdata.push_back(m.wdata[i]);
            end
            SMB_READ_BYTE, SMB_READ_WORD: begin
                t.kind = I2C_WRITE_READ;
                t.wdata.push_back(m.cmd);
                t.nrd = ((m.proto == SMB_READ_BYTE) ? 1 : 2) + p;
            end
            SMB_PROC_CALL: begin
                t.kind = I2C_WRITE_READ;
                t.wdata.push_back(m.cmd);
                foreach (m.wdata[i]) t.wdata.push_back(m.wdata[i]);
                t.nrd = 2 + p;
            end
            SMB_BLOCK_READ: begin
                t.kind = I2C_WRITE_READ;
                t.wdata.push_back(m.cmd);
                t.rd_count_hdr = 1;
                t.rd_extra = p;
            end
            SMB_BLOCK_PROC_CALL: begin
                t.kind = I2C_WRITE_READ;
                t.wdata.push_back(m.cmd);
                t.wdata.push_back(8'(m.wdata.size()));
                foreach (m.wdata[i]) t.wdata.push_back(m.wdata[i]);
                t.rd_count_hdr = 1;
                t.rd_extra = p;
            end
            default: `uvm_error(get_name(), {"cannot send ", m.convert2string()})
        endcase
        // the PEC of a write message: CRC over the address byte and every byte written
        if (m.pec && t.kind == I2C_WRITE && m.proto != SMB_QUICK_W) begin
            bit [7:0] msg[$];
            bit [7:0] pec;
            msg.push_back({m.addr, 1'b0});
            foreach (t.wdata[i]) msg.push_back(t.wdata[i]);
            pec = odve_smbus_pec(msg);
            if (m.bad_pec) pec = pec ^ 8'h5A;
            t.wdata.push_back(pec);
        end
        t.tmo_byte   = m.tmo_byte;
        t.tmo_cycles = m.tmo_cycles;
        t.abort_byte = m.abort_byte;
        t.abort_bit  = m.abort_bit;
        return t;
    endfunction

    function void from_i2c(odve_smbus_item m, odve_i2c_item t);
        bit [7:0] msg[$];
        int unsigned n;
        m.addr_ack  = t.addr_ack;
        m.ack       = t.addr_ack && !t.wr_nack;
        m.nack_byte = !t.addr_ack ? 0 : t.wr_nack ? t.wack.size() : -1;
        m.rdata.delete();
        m.pec_present = 0;
        m.pec_ok = 1;
        if (t.kind == I2C_WRITE) begin
            m.pec_present = m.pec && m.proto != SMB_QUICK_W && t.wack.size() == t.wdata.size();
            if (m.pec_present) m.pec_rx = t.wdata[t.wdata.size() - 1];
            return;
        end
        if (t.rdata.size() == 0) return;
        // the message so far, for the PEC check
        if (t.kind == I2C_WRITE_READ) begin
            msg.push_back({m.addr, 1'b0});
            foreach (t.wdata[i]) msg.push_back(t.wdata[i]);
        end
        msg.push_back({m.addr, 1'b1});
        if (t.rd_count_hdr) begin
            m.count = t.rdata[0];
            n = 1 + m.count;
            for (int i = 1; i < n && i < t.rdata.size(); i++) m.rdata.push_back(t.rdata[i]);
        end else begin
            n = t.nrd - (m.pec ? 1 : 0);
            for (int i = 0; i < n && i < t.rdata.size(); i++) m.rdata.push_back(t.rdata[i]);
        end
        if (m.pec && t.rdata.size() == n + 1) begin
            for (int i = 0; i < n; i++) msg.push_back(t.rdata[i]);
            m.pec_present = 1;
            m.pec_rx = t.rdata[n];
            m.pec_ok = odve_smbus_pec(msg) == m.pec_rx;
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_i2c_item_seq s;
        odve_i2c_item     t;
        forever begin
            seq_item_port.get_next_item(req);
            t = to_i2c(req);
            s = odve_i2c_item_seq::type_id::create("s");
            s.item = t;
            s.start(i2c_sqr);
            from_i2c(req, t);
            n_items++;
            `uvm_info(get_name(), req.convert2string(), UVM_HIGH)
            seq_item_port.item_done();
        end
    endtask
endclass
