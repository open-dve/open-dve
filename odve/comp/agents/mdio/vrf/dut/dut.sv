// RTL PHY management block: the MDIO slave of one PHY (IEEE 802.3 Clause 22)
// that is also one port with two MMDs (Clause 45) - PMA/PMD (1) and PCS (3).
//
// Plain synthesizable RTL on the system clock: MDC and MDIO are brought in
// through 2-flop synchronizers and MDIO is sampled at each synchronized MDC
// rising edge (both pass the same flops, so the sampled bit is the one at
// the edge). The output (mdio_o / mdio_oe, no tristate; the line is resolved
// outside with a pull-up) changes one clock after the edge is detected,
// i.e. after the rising edge of MDC, as Clause 22 asks of the PHY.
//
// Frame handling:
//   - >= PRE_MIN consecutive ones before ST, else the frame is followed but
//     ignored (no preamble suppression: status bit 6 = 0);
//   - ST=01: Clause 22, OP 01 write / 10 read at PHYAD; OP 00/11 ignored;
//   - ST=00: Clause 45 at PRTAD, DEVAD 1 or 3: OP 00 address, 01 write,
//     11 read, 10 read + post-increment of the MMD's address register;
//   - write-type frames apply only with TA=10;
//   - a read that is not addressed to this PHY leaves MDIO released.
// Register map (the agent's odve_mdio_phy_model mirrors it):
//   C22: 0 RW (reset BMCR_RST), 1 RO BMSR, 2/3 RO ID1/ID2, 4..31 RW (reset 0)
//   C45 per MMD: 0 RW, 1 RO MMD_STAT, 2/3 RO ID1/ID2, 5 RO DEVS, 6 RO 0,
//                0x8000..0x8000+NRW45-1 RW, everything else reads 0.
module dut #(
    parameter logic [4:0]  PHYAD    = 5'd1,
    parameter logic [4:0]  PRTAD    = 5'd1,
    parameter logic [15:0] ID1      = 16'h4F44,
    parameter logic [15:0] ID2      = 16'h5645,
    parameter logic [15:0] BMCR_RST = 16'h1140,
    parameter logic [15:0] BMSR     = 16'h780D,
    parameter logic [15:0] MMD_STAT = 16'h0004,
    parameter logic [15:0] DEVS     = 16'h000A,
    parameter int          PRE_MIN  = 32,
    parameter int          NRW45    = 16
) (
    input  logic clk,
    input  logic rst_n,
    input  logic mdc,
    input  logic mdio_i,
    output logic mdio_o,
    output logic mdio_oe
);
    typedef enum logic [2:0] { S_PRE, S_ST, S_OP, S_PA, S_RA, S_TA, S_DATA } state_e;

    // synchronizers and edge detect
    logic [1:0] mdc_s, mdio_s;
    logic       mdc_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mdc_s  <= '0;
            mdio_s <= 2'b11;
            mdc_q  <= 1'b0;
        end else begin
            mdc_s  <= {mdc_s[0], mdc};
            mdio_s <= {mdio_s[0], mdio_i};
            mdc_q  <= mdc_s[1];
        end
    end
    wire rise = mdc_s[1] & ~mdc_q;
    wire bin  = mdio_s[1];

    // registers
    logic [15:0] c22 [32];
    logic [15:0] mmd_addr [2];
    logic [15:0] mmd_ctrl [2];
    logic [15:0] mmd_rw   [2][NRW45];

    // frame state
    state_e      st;
    logic [5:0]  ones;       // saturates at 63
    logic [4:0]  cnt;
    logic        c45, ign;
    logic [1:0]  op;
    logic [4:0]  pa, ra;
    logic [1:0]  ta;
    logic [15:0] sh;         // read data out / write data in

    // decode of the frame header (valid from S_TA on)
    wire       mmd_ok  = (ra == 5'd1) || (ra == 5'd3);
    wire       mi      = (ra == 5'd3);                  // MMD index
    wire       hit     = !ign && (c45 ? (pa == PRTAD && mmd_ok) : (pa == PHYAD && (op == 2'b01 || op == 2'b10)));
    wire       is_rd   = c45 ? op[1] : (op == 2'b10);
    wire [15:0] a45    = mmd_addr[mi];
    wire        rw45   = (a45 >= 16'h8000) && (32'(a45) < 32'h8000 + NRW45);
    wire [15:0] widx   = a45 - 16'h8000;

    function automatic logic [15:0] c22_rd(input logic [4:0] r);
        case (r)
            5'd1:    return BMSR;
            5'd2:    return ID1;
            5'd3:    return ID2;
            default: return c22[r];
        endcase
    endfunction

    function automatic logic [15:0] c45_rd(input logic m, input logic [15:0] a);
        logic [15:0] i;
        i = a - 16'h8000;
        if (a == 16'd0)      return mmd_ctrl[m];
        else if (a == 16'd1) return MMD_STAT;
        else if (a == 16'd2) return ID1;
        else if (a == 16'd3) return ID2;
        else if (a == 16'd5) return DEVS;
        else if (a >= 16'h8000 && 32'(a) < 32'h8000 + NRW45) return mmd_rw[m][i[$clog2(NRW45)-1:0]];
        else                 return 16'h0;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st      <= S_PRE;
            ones    <= '0;
            cnt     <= '0;
            c45     <= 1'b0;
            ign     <= 1'b1;
            op      <= '0;
            pa      <= '0;
            ra      <= '0;
            ta      <= '0;
            sh      <= '0;
            mdio_o  <= 1'b1;
            mdio_oe <= 1'b0;
            for (int r = 0; r < 32; r++) c22[r] <= (r == 0) ? BMCR_RST : 16'h0;
            for (int m = 0; m < 2; m++) begin
                mmd_addr[m] <= '0;
                mmd_ctrl[m] <= '0;
                for (int k = 0; k < NRW45; k++) mmd_rw[m][k] <= '0;
            end
        end else if (rise) begin
            case (st)
                S_PRE: begin
                    if (bin) begin
                        if (ones != 6'h3F) ones <= ones + 6'd1;
                    end else begin                      // ST[1]
                        ign <= (32'(ones) < PRE_MIN);
                        st  <= S_ST;
                    end
                end
                S_ST: begin
                    c45 <= !bin;                        // 00: Clause 45, 01: Clause 22
                    cnt <= 5'd1;
                    st  <= S_OP;
                end
                S_OP: begin
                    op  <= {op[0], bin};
                    if (cnt == 5'd0) begin cnt <= 5'd4; st <= S_PA; end
                    else cnt <= cnt - 5'd1;
                end
                S_PA: begin
                    pa  <= {pa[3:0], bin};
                    if (cnt == 5'd0) begin cnt <= 5'd4; st <= S_RA; end
                    else cnt <= cnt - 5'd1;
                end
                S_RA: begin
                    ra  <= {ra[3:0], bin};
                    if (cnt == 5'd0) begin cnt <= 5'd1; st <= S_TA; end
                    else cnt <= cnt - 5'd1;
                end
                S_TA: begin
                    ta <= {ta[0], bin};
                    if (cnt == 5'd1) begin
                        // TA[1] just sampled: a read addressed here answers from now on
                        if (hit && is_rd) begin
                            mdio_oe <= 1'b1;
                            mdio_o  <= 1'b0;
                            sh      <= c45 ? c45_rd(mi, a45) : c22_rd(ra);
                        end
                        cnt <= 5'd0;
                    end else begin
                        if (hit && is_rd) mdio_o <= sh[15];
                        sh  <= {sh[14:0], 1'b0};
                        cnt <= 5'd15;
                        st  <= S_DATA;
                    end
                end
                S_DATA: begin
                    if (hit && is_rd) begin
                        mdio_o <= sh[15];
                        sh     <= {sh[14:0], 1'b0};
                        if (cnt == 5'd0) begin mdio_oe <= 1'b0; mdio_o <= 1'b1; end
                    end else begin
                        sh <= {sh[14:0], bin};
                    end
                    if (cnt == 5'd0) begin
                        st   <= S_PRE;
                        ones <= '0;
                        if (hit && !is_rd && ta == 2'b10) begin
                            if (!c45) begin
                                if (!(ra inside {5'd1, 5'd2, 5'd3})) c22[ra] <= {sh[14:0], bin};
                            end else if (op == 2'b00) begin
                                mmd_addr[mi] <= {sh[14:0], bin};
                            end else if (a45 == 16'd0) begin
                                mmd_ctrl[mi] <= {sh[14:0], bin};
                            end else if (rw45) begin
                                mmd_rw[mi][widx[$clog2(NRW45)-1:0]] <= {sh[14:0], bin};
                            end
                        end
                        if (hit && c45 && op == 2'b10) mmd_addr[mi] <= a45 + 16'd1;
                    end else begin
                        cnt <= cnt - 5'd1;
                    end
                end
                default: st <= S_PRE;
            endcase
        end
    end

    initial $display("Hi from DUT: MDIO PHY management block, PHYAD=%0d PRTAD=%0d", PHYAD, PRTAD);
endmodule
