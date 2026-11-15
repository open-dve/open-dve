// Register model of one or more MDIO PHYs (Clause 22) / ports with MMDs
// (Clause 45). Used three ways: by the slave driver in MEM mode, by the
// responding sequence in SEQ mode, and by the testbench scoreboard as the
// reference model of the RTL PHY in vrf/dut - the same register map as
// that DUT:
//
// Clause 22, per PHY address in phyads:
//   0      control      RW, reset ODVE_MDIO_BMCR_RST
//   1      status       RO  ODVE_MDIO_BMSR (MF preamble suppression bit 6 = 0)
//   2, 3   PHY ID       RO  id1, id2
//   4..31  RW storage, reset 0
// Clause 45, per port address in prtads, MMDs 1 (PMA/PMD) and 3 (PCS):
//   address register: set by an address frame, +1 after a post-read-increment read
//   0      control      RW, reset 0
//   1      status       RO  ODVE_MDIO_MMD_STAT
//   2, 3   device ID    RO  id1, id2
//   5      devices in package RO ODVE_MDIO_DEVS (bits 1 and 3)
//   6      devices in package (2) RO 0
//   0x8000..0x800F RW storage, reset 0
//   anything else reads 0, writes are ignored
// A frame is answered (claims) only with >= pre_min preamble ones, a defined
// opcode, a matching address (and present MMD), and, for write-type frames,
// TA = 10. Anything else leaves the line to the pull-up.
class odve_mdio_phy_model extends uvm_object;
    `uvm_object_utils(odve_mdio_phy_model)

    bit [4:0]    phyads[$];
    bit [4:0]    prtads[$];
    bit [15:0]   id1 = ODVE_MDIO_ID1;
    bit [15:0]   id2 = ODVE_MDIO_ID2;
    int unsigned pre_min = 32;

    bit [15:0]   c22  [bit [9:0]];    // {phyad, regad}
    bit [15:0]   c45a [bit [9:0]];    // address register per {prtad, devad}
    bit [15:0]   c45  [bit [25:0]];   // {prtad, devad, addr}

    function new(string name = "odve_mdio_phy_model");
        super.new(name);
    endfunction

    function void configure(odve_mdio_cfg cfg);
        phyads  = cfg.phyads;
        prtads  = cfg.prtads;
        id1     = cfg.id1;
        id2     = cfg.id2;
        pre_min = cfg.pre_min;
    endfunction

    function bit has_phy(bit [4:0] a);
        foreach (phyads[i]) if (phyads[i] == a) return 1;
        return 0;
    endfunction

    function bit has_mmd(bit [4:0] prtad, bit [4:0] devad);
        if (!(devad inside {ODVE_MDIO_MMD_PMA, ODVE_MDIO_MMD_PCS})) return 0;
        foreach (prtads[i]) if (prtads[i] == prtad) return 1;
        return 0;
    endfunction

    // Does a PHY of this model answer (read) / act on (write, address) the frame?
    // For a read only the header is needed (it is called before TA).
    function bit claims(odve_mdio_item tr);
        if (tr.pre_len < pre_min) return 0;
        if (tr.kind == ODVE_MDIO_C22_BAD) return 0;
        if (!tr.is_read() && tr.ta != 2'b10) return 0;
        return tr.is_c45() ? has_mmd(tr.phyad, tr.regad) : has_phy(tr.phyad);
    endfunction

    function bit [15:0] c22_rd(bit [4:0] pa, bit [4:0] ra);
        case (ra)
            5'd1: return ODVE_MDIO_BMSR;
            5'd2: return id1;
            5'd3: return id2;
            5'd0: return c22.exists({pa, ra}) ? c22[{pa, ra}] : ODVE_MDIO_BMCR_RST;
            default: return c22.exists({pa, ra}) ? c22[{pa, ra}] : 16'h0;
        endcase
    endfunction

    function bit c45_rw(bit [15:0] a);
        return a == 16'h0 || (a >= 16'h8000 && 32'(a) < 32'h8000 + ODVE_MDIO_NRW45);
    endfunction

    function bit [15:0] c45_rd(bit [4:0] pa, bit [4:0] dev, bit [15:0] a);
        case (a)
            16'd1:   return ODVE_MDIO_MMD_STAT;
            16'd2:   return id1;
            16'd3:   return id2;
            16'd5:   return ODVE_MDIO_DEVS;
            default: return (c45_rw(a) && c45.exists({pa, dev, a})) ? c45[{pa, dev, a}] : 16'h0;
        endcase
    endfunction

    function bit [15:0] addr_of(bit [4:0] pa, bit [4:0] dev);
        return c45a.exists({pa, dev}) ? c45a[{pa, dev}] : 16'h0;
    endfunction

    // Apply a claimed frame. Returns the read data for a read kind (and
    // performs the post-read increment); write-type frames update the model.
    function bit [15:0] access(odve_mdio_item tr);
        bit [15:0] a, d = '0;
        case (tr.kind)
            ODVE_MDIO_C22_WR: if (!(tr.regad inside {5'd1, 5'd2, 5'd3})) c22[{tr.phyad, tr.regad}] = tr.data;
            ODVE_MDIO_C22_RD: d = c22_rd(tr.phyad, tr.regad);
            ODVE_MDIO_C45_ADDR: c45a[{tr.phyad, tr.regad}] = tr.data;
            ODVE_MDIO_C45_WR: begin
                a = addr_of(tr.phyad, tr.regad);
                if (c45_rw(a)) c45[{tr.phyad, tr.regad, a}] = tr.data;
            end
            ODVE_MDIO_C45_RD, ODVE_MDIO_C45_RINC: begin
                a = addr_of(tr.phyad, tr.regad);
                d = c45_rd(tr.phyad, tr.regad, a);
                if (tr.kind == ODVE_MDIO_C45_RINC) c45a[{tr.phyad, tr.regad}] = a + 16'd1;
            end
            default: ;
        endcase
        return d;
    endfunction
endclass
