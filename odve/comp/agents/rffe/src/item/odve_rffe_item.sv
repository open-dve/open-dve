// One RFFE command sequence: SSC, command frame, address frame(s), data
// frames, bus park. No `rand`/constraints: user_randomize() draws every value
// from the odve_rand stream `rng` the sequence hands over, through
// `odve_rand(item).
//
// Frame numbering (inj_par_frame, the master's parity error injection):
// 0 = command frame, 1..naddr() = address frames, then the write data frames.
class odve_rffe_item extends uvm_sequence_item;
    `uvm_object_utils(odve_rffe_item)

    odve_rffe_kind_e kind   = ODVE_RFFE_REG_WR;
    bit [3:0]        usid   = 4'h5;   // slave address field of the command frame, 0 = broadcast
    bit [15:0]       addr   = '0;     // 5, 8 or 16 bits used, per kind; 0 for Register 0 Write
    int unsigned     nbytes = 1;      // data frames: 1 (register), 1..16 (extended), 1..8 (long)
    bit [7:0]        data[];          // write payload / read data (filled by the master driver and the monitor)
    bit [15:0]       nrf_mask = '0;   // read: bit k = data frame k was a No Response Frame (all zero incl. parity)

    // master: invert the parity bit of this frame, -1 = none
    int              inj_par_frame = -1;

    // observed by the monitor
    bit              cmd_par_err  = 0;
    bit              addr_par_err = 0;
    int              data_par_err_idx = -1;   // first write data frame with a parity error
    bit              half_speed = 0;          // read data clocked at a lower SCLK rate than the command

    // knobs of user_randomize()
    odve_rand        rng;
    bit [6:0]        kind_mask = 7'h7F;       // bit k enables odve_rffe_kind_e k
    bit [3:0]        usids[$];                // addressed slaves to pick from (empty: keep usid)
    int unsigned     nregs     = 64;          // implemented registers 0..nregs-1 of the slaves
    int unsigned     oor_pct   = 0;           // % of extended accesses starting beyond nregs
    int unsigned     bcast_pct = 0;           // % of writes sent to the broadcast USID 0
    int unsigned     inj_pct   = 0;           // % of items with an inverted parity bit

    function new(string name = "odve_rffe_item");
        super.new(name);
    endfunction

    function bit is_read();
        return kind inside {ODVE_RFFE_REG_RD, ODVE_RFFE_EXT_RD, ODVE_RFFE_EXTL_RD};
    endfunction

    function bit is_long();
        return kind inside {ODVE_RFFE_EXTL_WR, ODVE_RFFE_EXTL_RD};
    endfunction

    function int unsigned naddr();
        case (kind)
            ODVE_RFFE_EXT_WR, ODVE_RFFE_EXT_RD:   return 1;
            ODVE_RFFE_EXTL_WR, ODVE_RFFE_EXTL_RD: return 2;
            default:                              return 0;
        endcase
    endfunction

    function int unsigned max_bytes();
        case (kind)
            ODVE_RFFE_EXT_WR, ODVE_RFFE_EXT_RD:   return 16;
            ODVE_RFFE_EXTL_WR, ODVE_RFFE_EXTL_RD: return 8;
            default:                              return 1;
        endcase
    endfunction

    // frames the master drives: command + address + write data
    function int unsigned nframes_master();
        return 1 + naddr() + ((!is_read() && kind != ODVE_RFFE_REG0_WR) ? nbytes : 0);
    endfunction

    // address of data byte i: extended addresses wrap at 8 bits, long ones at 16
    function bit [15:0] byte_addr(int unsigned i);
        bit [15:0] a = addr + 16'(i);
        return is_long() ? a : {8'h00, a[7:0]};
    endfunction

    // the 8-bit command field
    function bit [7:0] cmd_byte();
        bit [7:0] bc = 8'(nbytes - 1);
        bit [7:0] d0 = (data.size() > 0) ? data[0] : 8'h00;
        case (kind)
            ODVE_RFFE_REG0_WR: return {1'b1, d0[6:0]};
            ODVE_RFFE_REG_WR:  return {3'b010, addr[4:0]};
            ODVE_RFFE_REG_RD:  return {3'b011, addr[4:0]};
            ODVE_RFFE_EXT_WR:  return {4'b0000, bc[3:0]};
            ODVE_RFFE_EXT_RD:  return {4'b0010, bc[3:0]};
            ODVE_RFFE_EXTL_WR: return {5'b00110, bc[2:0]};
            default:           return {5'b00111, bc[2:0]};   // EXTL_RD
        endcase
    endfunction

    // Decodes a command field into kind / addr / nbytes / data (Register 0
    // Write). Returns 0 for the codes the agent does not support (0001_xxxx).
    function bit decode(bit [7:0] c);
        addr   = '0;
        nbytes = 1;
        if (c[7]) begin
            kind = ODVE_RFFE_REG0_WR;
            data = new[1];
            data[0] = {1'b0, c[6:0]};
        end else if (c[7:6] == 2'b01) begin
            kind = c[5] ? ODVE_RFFE_REG_RD : ODVE_RFFE_REG_WR;
            addr = {11'h0, c[4:0]};
        end else if (c[7:4] == 4'b0000 || c[7:4] == 4'b0010) begin
            kind   = c[5] ? ODVE_RFFE_EXT_RD : ODVE_RFFE_EXT_WR;
            nbytes = int'(c[3:0]) + 1;
        end else if (c[7:4] == 4'b0011) begin
            kind   = c[3] ? ODVE_RFFE_EXTL_RD : ODVE_RFFE_EXTL_WR;
            nbytes = int'(c[2:0]) + 1;
        end else begin
            return 0;
        end
        return 1;
    endfunction

    function void user_randomize();
        odve_rffe_kind_e kinds[$];
        int unsigned     k;
        for (int i = 0; i < 7; i++) if (kind_mask[i]) kinds.push_back(odve_rffe_kind_e'(i));
        if (kinds.size() == 0) kinds.push_back(ODVE_RFFE_REG_WR);
        k    = rng.index(kinds.size());
        kind = kinds[k];
        if (usids.size() > 0) begin
            k    = rng.index(usids.size());
            usid = usids[k];
        end
        if (!is_read() && rng.chance(bcast_pct)) usid = 4'h0;
        nbytes = rng.urand(1, max_bytes());
        case (kind)
            ODVE_RFFE_REG0_WR:                 addr = '0;
            ODVE_RFFE_REG_WR, ODVE_RFFE_REG_RD: addr = 16'(rng.urange(31));
            ODVE_RFFE_EXT_WR, ODVE_RFFE_EXT_RD: begin
                if (rng.chance(oor_pct)) addr = 16'(rng.urand(nregs, 255));
                else                     addr = 16'(rng.urand(0, nregs - 1));
            end
            default: begin
                if (rng.chance(oor_pct)) addr = 16'(rng.urand(nregs, 65535));
                else                     addr = 16'(rng.urand(0, nregs - 1));
            end
        endcase
        data = new[nbytes];
        foreach (data[i]) data[i] = 8'(rng.urange(255));
        if (kind == ODVE_RFFE_REG0_WR) data[0][7] = 1'b0;
        nrf_mask = '0;
        inj_par_frame = -1;
        if (rng.chance(inj_pct)) inj_par_frame = int'(rng.urange(nframes_master() - 1));
    endfunction

    function string convert2string();
        string s = $sformatf("%s usid=%0h addr=0x%0h n=%0d", kind.name(), usid, addr, nbytes);
        if (data.size() > 0) begin
            s = {s, " data="};
            foreach (data[i]) s = {s, $sformatf("%s%02h", (i == 0) ? "" : ".", data[i])};
        end
        if (nrf_mask != 0)        s = {s, $sformatf(" nrf=%04h", nrf_mask)};
        if (inj_par_frame >= 0)   s = {s, $sformatf(" inj_par_frame=%0d", inj_par_frame)};
        if (cmd_par_err)          s = {s, " CMD_PAR_ERR"};
        if (addr_par_err)         s = {s, " ADDR_PAR_ERR"};
        if (data_par_err_idx >= 0) s = {s, $sformatf(" DATA_PAR_ERR@%0d", data_par_err_idx)};
        if (half_speed)           s = {s, " HALF_SPEED"};
        return s;
    endfunction
endclass
