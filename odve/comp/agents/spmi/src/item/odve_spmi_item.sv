// One SPMI command sequence: SSC, command frame, address frame(s), data
// frames, then for a read the slave's data frames and for every other
// command the ACK/NACK cycle, bus park. No `rand`/constraints:
// user_randomize() draws every value from the odve_rand stream `rng` the
// sequence hands over, through `odve_rand(item).
//
// Frame numbering (inj_par_frame, the master's parity error injection):
// 0 = command frame, 1..naddr() = address frames, then the write data frames.
class odve_spmi_item extends uvm_sequence_item;
    `uvm_object_utils(odve_spmi_item)

    odve_spmi_kind_e kind   = ODVE_SPMI_REG_WR;
    bit [3:0]        sid    = 4'h5;   // slave address field of the command frame
    bit [15:0]       addr   = '0;     // 5, 8 or 16 bits used, per kind; 0 for Register 0 Write and the PM commands
    int unsigned     nbytes = 1;      // data frames: 1 (register), 1..16 (extended), 1..8 (long); 0 for PM commands
    bit [7:0]        data[];          // write payload / read data (filled by the master driver and the monitor)
    bit [15:0]       nrf_mask = '0;   // read: bit k = data frame k was a No Response Frame (all zero incl. parity)
    bit              ack = 0;         // non-read commands: the ACK/NACK bit (1 = ACK), filled by the master and the monitor

    // master: invert the parity bit of this frame, -1 = none
    int              inj_par_frame = -1;

    // observed by the monitor
    bit              cmd_par_err  = 0;
    bit              addr_par_err = 0;
    int              data_par_err_idx = -1;   // first write data frame with a parity error

    // knobs of user_randomize()
    odve_rand        rng;
    bit [10:0]       kind_mask = 11'h07F;     // bit k enables odve_spmi_kind_e k (default: register commands)
    bit [3:0]        sids[$];                 // addressed slaves to pick from (empty: keep sid)
    int unsigned     nregs     = 64;          // implemented registers 0..nregs-1 of the slaves
    int unsigned     oor_pct   = 0;           // % of extended accesses starting beyond nregs
    int unsigned     inj_pct   = 0;           // % of items with an inverted parity bit

    function new(string name = "odve_spmi_item");
        super.new(name);
    endfunction

    function bit is_read();
        return kind inside {ODVE_SPMI_REG_RD, ODVE_SPMI_EXT_RD, ODVE_SPMI_EXTL_RD};
    endfunction

    function bit is_pm();
        return kind inside {ODVE_SPMI_RESET, ODVE_SPMI_SLEEP, ODVE_SPMI_SHUTDOWN, ODVE_SPMI_WAKEUP};
    endfunction

    function bit is_long();
        return kind inside {ODVE_SPMI_EXTL_WR, ODVE_SPMI_EXTL_RD};
    endfunction

    // write data frames follow the command/address frames
    function bit has_wdata();
        return kind inside {ODVE_SPMI_REG_WR, ODVE_SPMI_EXT_WR, ODVE_SPMI_EXTL_WR};
    endfunction

    function int unsigned naddr();
        case (kind)
            ODVE_SPMI_EXT_WR, ODVE_SPMI_EXT_RD:   return 1;
            ODVE_SPMI_EXTL_WR, ODVE_SPMI_EXTL_RD: return 2;
            default:                              return 0;
        endcase
    endfunction

    function int unsigned max_bytes();
        case (kind)
            ODVE_SPMI_EXT_WR, ODVE_SPMI_EXT_RD:   return 16;
            ODVE_SPMI_EXTL_WR, ODVE_SPMI_EXTL_RD: return 8;
            default:                              return 1;
        endcase
    endfunction

    // frames the master drives: command + address + write data
    function int unsigned nframes_master();
        return 1 + naddr() + (has_wdata() ? nbytes : 0);
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
            ODVE_SPMI_REG0_WR:  return {1'b1, d0[6:0]};
            ODVE_SPMI_REG_WR:   return {3'b010, addr[4:0]};
            ODVE_SPMI_REG_RD:   return {3'b011, addr[4:0]};
            ODVE_SPMI_EXT_WR:   return {4'b0000, bc[3:0]};
            ODVE_SPMI_EXT_RD:   return {4'b0010, bc[3:0]};
            ODVE_SPMI_EXTL_WR:  return {5'b00110, bc[2:0]};
            ODVE_SPMI_EXTL_RD:  return {5'b00111, bc[2:0]};
            ODVE_SPMI_RESET:    return 8'h10;
            ODVE_SPMI_SLEEP:    return 8'h11;
            ODVE_SPMI_SHUTDOWN: return 8'h12;
            default:            return 8'h13;   // WAKEUP
        endcase
    endfunction

    // Decodes a command field into kind / addr / nbytes / data (Register 0
    // Write). Returns 0 for the codes the agent does not support
    // (Authenticate, Master Read/Write, Transfer Bus Ownership, DDB, reserved).
    function bit decode(bit [7:0] c);
        addr   = '0;
        nbytes = 1;
        if (c[7]) begin
            kind = ODVE_SPMI_REG0_WR;
            data = new[1];
            data[0] = {1'b0, c[6:0]};
        end else if (c[7:6] == 2'b01) begin
            kind = c[5] ? ODVE_SPMI_REG_RD : ODVE_SPMI_REG_WR;
            addr = {11'h0, c[4:0]};
        end else if (c[7:4] == 4'b0000 || c[7:4] == 4'b0010) begin
            kind   = c[5] ? ODVE_SPMI_EXT_RD : ODVE_SPMI_EXT_WR;
            nbytes = int'(c[3:0]) + 1;
        end else if (c[7:4] == 4'b0011) begin
            kind   = c[3] ? ODVE_SPMI_EXTL_RD : ODVE_SPMI_EXTL_WR;
            nbytes = int'(c[2:0]) + 1;
        end else if (c[7:2] == 6'b000100) begin
            kind   = odve_spmi_kind_e'(int'(ODVE_SPMI_RESET) + int'(c[1:0]));
            nbytes = 0;
            data   = new[0];
        end else begin
            return 0;
        end
        return 1;
    endfunction

    function void user_randomize();
        odve_spmi_kind_e kinds[$];
        int unsigned     k;
        for (int i = 0; i < 11; i++) if (kind_mask[i]) kinds.push_back(odve_spmi_kind_e'(i));
        if (kinds.size() == 0) kinds.push_back(ODVE_SPMI_REG_WR);
        k    = rng.index(kinds.size());
        kind = kinds[k];
        if (sids.size() > 0) begin
            k   = rng.index(sids.size());
            sid = sids[k];
        end
        nbytes = is_pm() ? 0 : rng.urand(1, max_bytes());
        case (kind)
            ODVE_SPMI_REG_WR, ODVE_SPMI_REG_RD: addr = 16'(rng.urange(31));
            ODVE_SPMI_EXT_WR, ODVE_SPMI_EXT_RD: begin
                if (rng.chance(oor_pct)) addr = 16'(rng.urand(nregs, 255));
                else                     addr = 16'(rng.urand(0, nregs - 1));
            end
            ODVE_SPMI_EXTL_WR, ODVE_SPMI_EXTL_RD: begin
                if (rng.chance(oor_pct)) addr = 16'(rng.urand(nregs, 65535));
                else                     addr = 16'(rng.urand(0, nregs - 1));
            end
            default: addr = '0;
        endcase
        data = new[nbytes];
        foreach (data[i]) data[i] = 8'(rng.urange(255));
        if (kind == ODVE_SPMI_REG0_WR) data[0][7] = 1'b0;
        nrf_mask = '0;
        ack = 0;
        inj_par_frame = -1;
        if (rng.chance(inj_pct)) inj_par_frame = int'(rng.urange(nframes_master() - 1));
    endfunction

    function string convert2string();
        string s = $sformatf("%s sid=%0h", kind.name(), sid);
        if (!is_pm()) s = {s, $sformatf(" addr=0x%0h n=%0d", addr, nbytes)};
        if (data.size() > 0) begin
            s = {s, " data="};
            foreach (data[i]) s = {s, $sformatf("%s%02h", (i == 0) ? "" : ".", data[i])};
        end
        if (nrf_mask != 0)         s = {s, $sformatf(" nrf=%04h", nrf_mask)};
        if (!is_read())            s = {s, ack ? " ACK" : " NACK"};
        if (inj_par_frame >= 0)    s = {s, $sformatf(" inj_par_frame=%0d", inj_par_frame)};
        if (cmd_par_err)           s = {s, " CMD_PAR_ERR"};
        if (addr_par_err)          s = {s, " ADDR_PAR_ERR"};
        if (data_par_err_idx >= 0) s = {s, $sformatf(" DATA_PAR_ERR@%0d", data_par_err_idx)};
        return s;
    endfunction
endclass
