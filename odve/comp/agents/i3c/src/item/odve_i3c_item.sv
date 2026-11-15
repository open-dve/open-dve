// One I3C SDR transfer. No `rand`/constraints (ModelSim SE has no solver,
// see comp/agents/README.md): user_randomize() takes every value from the
// odve_rand stream `rng` the sequence hands over, reached through
// `odve_rand(item).
class odve_i3c_item extends uvm_sequence_item;
    `uvm_object_utils(odve_i3c_item)

    // ---- request (controller) / observation (monitor)
    odve_i3c_kind_e kind = I3C_PRIV_WR;
    bit [6:0]    addr;             // dynamic address; SETDASA: static address; IBI: the winner's address
    bit          rnw;              // header RnW of the addressed segment
    bit [7:0]    ccc;              // CCC code (CCC kinds, ENTDAA)
    bit [7:0]    data[$];          // write payload / read data / IBI Mandatory Data Byte
    int unsigned len      = 1;     // reads: the most bytes the controller takes (it aborts after that)
    bit          use_7e   = 1;     // private: S 7E/W ACK Sr <addr> (else S <addr>, arbitrated)
    int          perr_idx = -1;    // controller: send a wrong T-bit on this write byte;
                                   // ENTDAA: a wrong parity bit on this round's address
    bit [6:0]    da_pool[$];       // ENTDAA: the address to offer in each round

    // ---- results
    bit          ack;              // address ACK (IBI/Hot-Join: the controller's ACK)
    bit          t_end;            // read: the target ended it (T=0); else the controller aborted
    int unsigned n_perr;           // monitor: write bytes whose T-bit was wrong
    bit          bc_7e;            // monitor: a private transfer that followed a 7E/W header
    bit [63:0]   daa_id[$];        // ENTDAA, per round: {PID, BCR, DCR} the winner sent
    bit [6:0]    daa_da[$];        //   the address offered
    bit          daa_par_ok[$];    //   its parity was right
    bit          daa_ack[$];       //   and the winner ACKed it

    // ---- knobs of user_randomize()
    odve_rand    rng;
    bit [6:0]    tgt_addrs[$];     // where private transfers may go
    int unsigned nregs   = 16;     // register pointer range of the targets
    int unsigned max_len = 8;      // payload bytes

    function new(string name = "odve_i3c_item");
        super.new(name);
    endfunction

    // A random private transfer: write (pointer byte + data) or read.
    function void user_randomize();
        int unsigned n;
        if (rng == null) rng = new(get_full_name());
        kind = rng.chance(50) ? I3C_PRIV_WR : I3C_PRIV_RD;
        if (tgt_addrs.size() > 0) addr = tgt_addrs[rng.index(tgt_addrs.size())];
        rnw  = (kind == I3C_PRIV_RD);
        data.delete();
        if (kind == I3C_PRIV_WR) begin
            n = rng.urand(1, max_len);
            data.push_back(8'(rng.urange(nregs - 1)));      // register pointer
            for (int i = 1; i < n; i++) data.push_back(8'(rng.u16()));
        end else begin
            len = rng.urand(1, max_len);
        end
        perr_idx = -1;
        use_7e   = 1;
    endfunction

    function string kind_name();
        return kind.name();
    endfunction

    function string convert2string();
        string s = $sformatf("%s addr=0x%02h", kind.name(), addr);
        if (kind inside {I3C_CCC_BC, I3C_CCC_DW, I3C_CCC_DR, I3C_ENTDAA}) s = {s, $sformatf(" ccc=0x%02h", ccc)};
        s = {s, $sformatf(" ack=%0b", ack)};
        if (data.size() > 0) begin
            s = {s, " data="};
            foreach (data[i]) s = {s, $sformatf("%02h", data[i])};
        end
        if (kind inside {I3C_PRIV_RD, I3C_CCC_DR}) s = {s, $sformatf(" t_end=%0b", t_end)};
        if (n_perr > 0) s = {s, $sformatf(" PARITY_ERR=%0d", n_perr)};
        foreach (daa_id[i])
            s = {s, $sformatf(" [id=%016h da=0x%02h par_ok=%0b ack=%0b]", daa_id[i], daa_da[i], daa_par_ok[i], daa_ack[i])};
        return s;
    endfunction
endclass
