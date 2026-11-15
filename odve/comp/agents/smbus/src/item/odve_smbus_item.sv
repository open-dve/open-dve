// One SMBus message (SMBus 3.3 6.5), as the master driver sends it and as
// the monitor decodes it from the I2C transfer underneath.
//   cmd     command code; for Send Byte the byte sent
//   wdata   data written after the command: 1 byte (Write Byte), 2 (Word /
//           Process Call, low byte first), N (Block Write / Block Process
//           Call - the byte count is added on the bus, not stored here)
//   rdata   data read: 1 (Receive/Read Byte), 2 (Read Word / Process Call),
//           N (Block Read / Block Process Call - without the count)
class odve_smbus_item extends uvm_sequence_item;
    `uvm_object_utils(odve_smbus_item)

    // ---- request ----------------------------------------------------------
    odve_smbus_proto_e proto = SMB_WRITE_BYTE;
    bit [6:0]          addr  = 7'h3A;
    bit [7:0]          cmd   = 8'h00;
    bit [7:0]          wdata[$];
    bit                pec   = 0;        // append (write) / read (read) the PEC byte
    // error injection (master)
    bit                bad_pec    = 0;   // send a wrong PEC
    int                tmo_byte   = -1;  // hold SCL low after this byte (address = 0) ...
    int unsigned       tmo_cycles = 0;   // ... this many cycles, then STOP
    int                abort_byte = -1;  // STOP inside this byte ...
    int unsigned       abort_bit  = 3;   // ... after this many bits

    // ---- response / observation --------------------------------------------
    bit [7:0]          rdata[$];
    int unsigned       count     = 0;    // block reads: the byte count received
    int unsigned       wcount    = 0;    // block writes: the byte count sent (monitor; = wdata.size() unless injected)
    bit                addr_ack  = 0;
    bit                ack       = 0;    // every byte the target received was ACKed (address, command, data, PEC)
    int                nack_byte = -1;   // index of the first NACKed byte (0 = address), -1 = none
    bit                pec_present = 0;  // a PEC byte was transferred
    bit [7:0]          pec_rx    = 0;    // ... its value
    bit                pec_ok    = 1;    // ... and it matched
    bit                complete  = 0;    // monitor: the message has the protocol's full length
    bit                timeout   = 0;    // monitor: SCL was held low >= tTIMEOUT,MIN during the message
    bit                aborted   = 0;    // monitor: START/STOP inside a byte
    bit                alert     = 0;    // monitor: SMBALERT# was asserted when the message ended
    int unsigned       nbytes    = 0;    // monitor: bytes on the bus, address bytes included
    bit [7:0]          raw_wr[$];        // monitor: every byte written after the address (command, count, data, PEC ...)
    bit [7:0]          raw_rd[$];        // monitor: every byte read (count, data, PEC ...)

    // ---- knobs of user_randomize() -----------------------------------------
    odve_rand          rng;
    bit [6:0]          tgt_addr  = 7'h3A;
    int unsigned       p_pec     = 50;          // % of messages with PEC
    int unsigned       max_blk   = 32;          // block lengths 0..max_blk
    // weights per protocol, odve_smbus_proto_e order (ARA/UNKNOWN: keep 0)
    int unsigned       w_proto[] = '{1, 1, 2, 2, 3, 3, 3, 3, 2, 3, 3, 2, 0, 0};
    // the device's command codes per kind (a kind with no codes is not drawn)
    bit [7:0]          cmds_send[$], cmds_byte[$], cmds_word[$], cmds_pcall[$], cmds_block[$], cmds_bpcall[$];

    function new(string name = "odve_smbus_item");
        super.new(name);
    endfunction

    function bit [7:0] pick(bit [7:0] q[$]);
        return q[rng.index(q.size())];
    endfunction

    // A message the device understands: protocol by weight, a command code of
    // the matching kind, random data, PEC with p_pec %.
    function void user_randomize();
        int unsigned w[];
        int unsigned n;
        if (rng == null) rng = new("odve_smbus_item");
        w = w_proto;
        if (cmds_send.size() == 0)   w[SMB_SEND_BYTE] = 0;
        if (cmds_byte.size() == 0)   begin w[SMB_WRITE_BYTE] = 0; w[SMB_READ_BYTE] = 0; end
        if (cmds_word.size() == 0)   begin w[SMB_WRITE_WORD] = 0; w[SMB_READ_WORD] = 0; end
        if (cmds_pcall.size() == 0)  w[SMB_PROC_CALL] = 0;
        if (cmds_block.size() == 0)  begin w[SMB_BLOCK_WRITE] = 0; w[SMB_BLOCK_READ] = 0; end
        if (cmds_bpcall.size() == 0) w[SMB_BLOCK_PROC_CALL] = 0;
        proto = odve_smbus_proto_e'(rng.weighted(w));
        addr  = tgt_addr;
        pec   = rng.chance(p_pec);
        wdata.delete();
        rdata.delete();
        case (proto)
            SMB_SEND_BYTE:                 cmd = pick(cmds_send);
            SMB_WRITE_BYTE, SMB_READ_BYTE: cmd = pick(cmds_byte);
            SMB_WRITE_WORD, SMB_READ_WORD: cmd = pick(cmds_word);
            SMB_PROC_CALL:                 cmd = pick(cmds_pcall);
            SMB_BLOCK_WRITE, SMB_BLOCK_READ: cmd = pick(cmds_block);
            SMB_BLOCK_PROC_CALL:           cmd = pick(cmds_bpcall);
            default:                       cmd = 8'h00;
        endcase
        case (proto)
            SMB_WRITE_BYTE: n = 1;
            SMB_WRITE_WORD, SMB_PROC_CALL: n = 2;
            SMB_BLOCK_WRITE, SMB_BLOCK_PROC_CALL: n = rng.urand(0, max_blk);
            default: n = 0;
        endcase
        repeat (n) wdata.push_back(8'(rng.u16()));
    endfunction

    function bit is_read();
        return proto inside {SMB_QUICK_R, SMB_RECV_BYTE, SMB_READ_BYTE, SMB_READ_WORD, SMB_PROC_CALL,
                             SMB_BLOCK_READ, SMB_BLOCK_PROC_CALL, SMB_ARA};
    endfunction

    function string convert2string();
        string s = $sformatf("%s @0x%02h", odve_smbus_proto_str(proto), addr);
        if (!(proto inside {SMB_QUICK_W, SMB_QUICK_R, SMB_RECV_BYTE, SMB_ARA})) s = {s, $sformatf(" cmd=%02h", cmd)};
        if (wdata.size() > 0) begin
            s = {s, " w:"};
            foreach (wdata[i]) s = {s, $sformatf(" %02h", wdata[i])};
        end
        if (rdata.size() > 0) begin
            s = {s, " r:"};
            foreach (rdata[i]) s = {s, $sformatf(" %02h", rdata[i])};
        end
        if (pec_present) s = {s, $sformatf(" pec=%02h%s", pec_rx, pec_ok ? "" : "(BAD)")};
        if (!ack)    s = {s, $sformatf(" NACK@%0d", nack_byte)};
        if (timeout) s = {s, " TIMEOUT"};
        if (aborted) s = {s, " ABORTED"};
        if (alert)   s = {s, " ALERT"};
        return s;
    endfunction

    virtual function void do_copy(uvm_object rhs);
        odve_smbus_item o;
        super.do_copy(rhs);
        if (!$cast(o, rhs)) return;
        proto = o.proto; addr = o.addr; cmd = o.cmd; wdata = o.wdata; pec = o.pec; bad_pec = o.bad_pec;
        tmo_byte = o.tmo_byte; tmo_cycles = o.tmo_cycles; abort_byte = o.abort_byte; abort_bit = o.abort_bit;
        rdata = o.rdata; count = o.count; wcount = o.wcount; addr_ack = o.addr_ack; ack = o.ack; nack_byte = o.nack_byte;
        pec_present = o.pec_present; pec_rx = o.pec_rx; pec_ok = o.pec_ok; complete = o.complete;
        timeout = o.timeout; aborted = o.aborted; alert = o.alert; nbytes = o.nbytes;
        raw_wr = o.raw_wr; raw_rd = o.raw_rd;
    endfunction
endclass
