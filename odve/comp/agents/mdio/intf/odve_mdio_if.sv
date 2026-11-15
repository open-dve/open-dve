// MDIO / MDC management interface (IEEE 802.3 Clause 22 and Clause 45).
//
// MDC is driven by the station management entity (STA, the master agent's
// driver). MDIO is a bidirectional, pulled-up line. No inout/tri: every
// possible driver has its own value/enable pair and the line is resolved
// here with plain logic, so Verilator and Questa see the same thing:
//
//   sta_o / sta_oe   master agent (STA)
//   phy_o / phy_oe   slave agent (PHY/MMD register model), when it plays a PHY
//   dut_o / dut_oe   RTL PHY in vrf/dut, wired from top (gated by +mdio_slave)
//
// mdio = 1 when nobody drives (the pull-up); a driver's 0 wins (wired-AND),
// and two enables at once is contention, which the monitor reports.
interface odve_mdio_if (
    input logic clk,      // system clock: everything is cycle based on it
    input logic rst_n
);
    logic mdc    = 1'b0;
    logic sta_o  = 1'b1;
    logic sta_oe = 1'b0;
    logic phy_o  = 1'b1;
    logic phy_oe = 1'b0;
    logic dut_o;
    logic dut_oe;
    logic mdio;

    assign mdio = (~sta_oe | sta_o) & (~phy_oe | phy_o) & (~dut_oe | dut_o);
endinterface
