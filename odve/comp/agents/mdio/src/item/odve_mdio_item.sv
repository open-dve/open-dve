// One MDIO management frame:
//
//   PRE (pre_len x 1) | ST(2) | OP(2) | PHYAD/PRTAD(5) | REGAD/DEVAD(5) | TA(2) | DATA(16) | IDLE
//
// No `rand`/constraints (comp/agents/README.md): user_randomize() takes its
// values from the odve_rand stream in `rng`, set by the sequence.
class odve_mdio_item extends uvm_sequence_item;
    `uvm_object_utils(odve_mdio_item)

    odve_mdio_kind_e kind  = ODVE_MDIO_C22_RD;
    bit [4:0]        phyad;          // Clause 22 PHYAD, Clause 45 PRTAD
    bit [4:0]        regad;          // Clause 22 REGAD, Clause 45 DEVAD
    bit [15:0]       data;           // write data / address (C45_ADDR) / read data after the frame
    int unsigned     pre_len = 32;   // preamble ones the STA drives (monitor: ones seen before ST)
    int unsigned     idle    = 1;    // MDC cycles with MDIO released after the frame (0 = back to back)
    bit [1:0]        ta      = 2'b10;// write-type TA the STA drives (monitor: the TA seen)
    bit [1:0]        bad_op  = 2'b00;// OP sent for ODVE_MDIO_C22_BAD (00 or 11)
    // results: filled in by the master driver (read) and the monitor
    bit              resp;           // a PHY drove TA[0]=0 and the data of a read frame
    int unsigned     n_err;          // monitor: protocol violations found in this frame

    // user_randomize() knobs
    odve_rand        rng;
    bit [4:0]        addrs[$] = '{5'd1};  // responding PHY/port addresses
    int unsigned     miss_pct = 0;        // % of frames to a non-responding address or MMD
    int unsigned     w_kind[] = '{2, 2, 2, 2, 2, 1};  // weights of kinds 0..5

    function new(string name = "odve_mdio_item");
        super.new(name);
    endfunction

    function bit is_c45();  return kind inside {ODVE_MDIO_C45_ADDR, ODVE_MDIO_C45_WR, ODVE_MDIO_C45_RD, ODVE_MDIO_C45_RINC}; endfunction
    function bit is_read(); return kind inside {ODVE_MDIO_C22_RD, ODVE_MDIO_C45_RD, ODVE_MDIO_C45_RINC}; endfunction
    function bit [1:0] st(); return is_c45() ? 2'b00 : 2'b01; endfunction
    function bit [1:0] op();
        case (kind)
            ODVE_MDIO_C22_WR:   return 2'b01;
            ODVE_MDIO_C22_RD:   return 2'b10;
            ODVE_MDIO_C45_ADDR: return 2'b00;
            ODVE_MDIO_C45_WR:   return 2'b01;
            ODVE_MDIO_C45_RD:   return 2'b11;
            ODVE_MDIO_C45_RINC: return 2'b10;
            default:            return bad_op;
        endcase
    endfunction

    // ST/OP back to a kind (the monitor and the slave driver decode frames with it).
    static function odve_mdio_kind_e decode(bit [1:0] st, bit [1:0] op);
        if (st == 2'b01) return (op == 2'b01) ? ODVE_MDIO_C22_WR : (op == 2'b10) ? ODVE_MDIO_C22_RD : ODVE_MDIO_C22_BAD;
        case (op)
            2'b00:   return ODVE_MDIO_C45_ADDR;
            2'b01:   return ODVE_MDIO_C45_WR;
            2'b11:   return ODVE_MDIO_C45_RD;
            default: return ODVE_MDIO_C45_RINC;
        endcase
    endfunction

    // Register numbers worth hitting: the standard ones and the RW window.
    function bit [15:0] pick_c45_addr();
        case (rng.urange(3))
            0:       return 16'(rng.urange(6));               // control/status/ID/devices in package
            1, 2:    return 16'h8000 + 16'(rng.urange(15));   // vendor RW window
            default: return 16'(rng.u16());                   // anywhere (mostly unimplemented)
        endcase
    endfunction

    function void user_randomize();
        int unsigned k;
        if (rng == null) rng = new(get_full_name());
        k     = rng.weighted(w_kind);
        kind  = odve_mdio_kind_e'(k);
        if (miss_pct != 0 && rng.chance(miss_pct)) begin
            // a PHY/port address nobody answers, or (C45) an MMD that is not there
            bit [4:0] a;
            do a = 5'(rng.urange(31)); while (a inside {addrs});
            phyad = a;
        end else begin
            phyad = addrs[rng.index(addrs.size())];
        end
        if (is_c45()) regad = rng.chance(10) ? 5'(rng.urange(31)) : (rng.chance(50) ? 5'd1 : 5'd3);
        else          regad = 5'(rng.urange(31));
        if (kind == ODVE_MDIO_C45_ADDR) data = pick_c45_addr();
        else                            data = 16'(rng.u16());
        if (is_read()) data = '0;
        pre_len = 32;
        idle    = 1;
        ta      = 2'b10;
        resp    = 0;
    endfunction

    function string kind_name();
        case (kind)
            ODVE_MDIO_C22_WR:   return "C22_WR";
            ODVE_MDIO_C22_RD:   return "C22_RD";
            ODVE_MDIO_C45_ADDR: return "C45_ADDR";
            ODVE_MDIO_C45_WR:   return "C45_WR";
            ODVE_MDIO_C45_RD:   return "C45_RD";
            ODVE_MDIO_C45_RINC: return "C45_RINC";
            default:            return "C22_BADOP";
        endcase
    endfunction

    function string convert2string();
        return $sformatf("%-9s %s=%0d %s=%0d data=0x%04h pre=%0d ta=%02b%s", kind_name(),
                         is_c45() ? "prtad" : "phyad", phyad, is_c45() ? "devad" : "regad", regad,
                         data, pre_len, ta, is_read() ? (resp ? " resp" : " NO-RESP") : "");
    endfunction
endclass
