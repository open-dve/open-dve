// One I2C transfer from START to STOP, as the master driver executes it and
// as the monitor reconstructs it from the pins. No `rand`/constraints
// (comp/agents/README.md): user_randomize() draws from an odve_rand stream,
// reached through `odve_rand(item).
class odve_i2c_item extends uvm_sequence_item;
    `uvm_object_utils(odve_i2c_item)

    // ---- request ----------------------------------------------------------
    odve_i2c_kind_e kind   = I2C_WRITE;
    bit [9:0]       addr   = 10'h050;   // 7-bit address in [6:0] unless addr10
    bit             addr10 = 0;
    bit [7:0]       wdata[$];           // bytes written after the address
    int unsigned    nrd    = 0;         // bytes read (0 with I2C_READ: address only, then STOP)
    bit             rd_count_hdr = 0;   // the first byte read is a count: nrd = 1 + count + rd_extra
    int unsigned    rd_extra     = 0;   // with rd_count_hdr: bytes read after the counted ones (an SMBus PEC)

    // error injection (master driver)
    int          abort_byte = -1;       // STOP inside this byte (0 = first address byte), written bytes only
    int unsigned abort_bit  = 3;        //   after this many bits (1..7)
    int          tmo_byte   = -1;       // after this byte's acknowledge, hold SCL low ...
    int unsigned tmo_cycles = 0;        //   ... this many clk cycles, then STOP (SMBus tTIMEOUT)

    // ---- response / observation --------------------------------------------
    bit          addr_ack = 0;          // every address byte acknowledged
    bit          wack[$];               // acknowledge of each written byte (wdata order; may be shorter than wdata)
    bit          wr_nack  = 0;          // a written byte was NACKed (the transfer then ended)
    bit [7:0]    rdata[$];              // bytes read
    bit          mack_last = 0;         // monitor: the controller ACKed the last byte it read (protocol error)
    bit          aborted  = 0;          // monitor: START/STOP inside a byte
    bit          stretched = 0;         // monitor: a target held SCL low (clock stretching)
    int unsigned max_scl_low = 0;       // monitor: longest SCL low period, clk cycles
    bit          is_gc     = 0;         // monitor: general call (address 0, write)

    // ---- knobs of user_randomize() -----------------------------------------
    odve_rand    rng;                   // set by the sequence (a spawned stream); own stream if null
    bit [6:0]    tgt_addr7  = 7'h50;
    bit [9:0]    tgt_addr10 = 10'h2A5;
    int unsigned p_addr10   = 0;        // % of 10-bit transfers
    int unsigned p_bad_addr = 0;        // % of transfers to an address nobody answers
    int unsigned p_bad_ptr  = 0;        // % of register pointers out of range (the target NACKs them)
    int unsigned nregs      = 16;
    int unsigned max_wr     = 8;        // data bytes after the pointer byte
    int unsigned max_rd     = 8;
    int unsigned w_kind[]   = '{1, 1, 1};   // weights of WRITE, READ, WRITE_READ

    function new(string name = "odve_i2c_item");
        super.new(name);
    endfunction

    // A register-style transfer to the target: the first written byte is a
    // register pointer, then data; reads continue from the pointer.
    function void user_randomize();
        int unsigned n;
        if (rng == null) rng = new("odve_i2c_item");
        kind   = odve_i2c_kind_e'(rng.weighted(w_kind));
        addr10 = rng.chance(p_addr10);
        if (rng.chance(p_bad_addr)) begin
            if (addr10) begin
                addr = 10'(rng.urand(0, 1022));
                if (addr >= tgt_addr10) addr++;
            end else begin
                addr = 10'(rng.urand(8, 8'h76));          // not reserved (0000xxx, 1111xxx)
                if (addr >= 10'(tgt_addr7)) addr++;
            end
        end else begin
            addr = addr10 ? tgt_addr10 : 10'(tgt_addr7);
        end
        wdata.delete();
        rdata.delete();
        wack.delete();
        if (kind != I2C_READ) begin
            if (rng.chance(p_bad_ptr)) wdata.push_back(8'(rng.urand(nregs, 255)));
            else                       wdata.push_back(8'(rng.urand(0, nregs - 1)));
            if (kind == I2C_WRITE) begin
                n = rng.urand(0, max_wr);
                repeat (n) wdata.push_back(8'(rng.u16()));
            end
        end
        nrd = (kind == I2C_WRITE) ? 0 : rng.urand(1, max_rd);
    endfunction

    function string kind_str();
        case (kind)
            I2C_WRITE: return "WR";
            I2C_READ:  return "RD";
            default:   return "WR_RD";
        endcase
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("%s %s0x%0h %s", kind_str(), addr10 ? "a10=" : "a7=", addr, addr_ack ? "ACK" : "NACK");
        if (wdata.size() > 0) begin
            s = {s, " w:"};
            foreach (wdata[i]) s = {s, $sformatf(" %02h%s", wdata[i], (i < wack.size() && !wack[i]) ? "(N)" : "")};
        end
        if (rdata.size() > 0) begin
            s = {s, " r:"};
            foreach (rdata[i]) s = {s, $sformatf(" %02h", rdata[i])};
        end else if (kind != I2C_WRITE) s = {s, $sformatf(" nrd=%0d", nrd)};
        if (is_gc)     s = {s, " GC"};
        if (aborted)   s = {s, " ABORTED"};
        if (stretched) s = {s, " STRETCHED"};
        return s;
    endfunction

    virtual function void do_copy(uvm_object rhs);
        odve_i2c_item o;
        super.do_copy(rhs);
        if (!$cast(o, rhs)) return;
        kind = o.kind; addr = o.addr; addr10 = o.addr10; wdata = o.wdata; nrd = o.nrd;
        rd_count_hdr = o.rd_count_hdr; rd_extra = o.rd_extra;
        abort_byte = o.abort_byte; abort_bit = o.abort_bit; tmo_byte = o.tmo_byte; tmo_cycles = o.tmo_cycles;
        addr_ack = o.addr_ack; wack = o.wack; wr_nack = o.wr_nack; rdata = o.rdata; mack_last = o.mack_last;
        aborted = o.aborted; stretched = o.stretched; max_scl_low = o.max_scl_low; is_gc = o.is_gc;
    endfunction
endclass
