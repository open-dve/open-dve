// I2S bus: SCK (bit clock), WS (word select / LRCLK / frame sync), SD
// (serial data) and an optional MCLK. All three bus lines are push-pull
// with exactly one driver each: SCK and WS come from the clock controller
// (the agent or the device on the other side), SD from the transmitter.
// No tristates: every possible driver has its own value + output enable,
// and the bus value is a plain mux below. Two enables on at once is bus
// contention - the monitor reports it.
//
//   a_*  the agent's drive (a clock-controller agent writes a_sck/a_ws/
//        a_clk_oe, a transmitter agent writes a_sd/a_sd_oe; an agent never
//        writes the other group)
//   d_*  the device on the other side (the DUT), wired from top
interface odve_i2s_if (
    input logic clk,      // TB/system reference clock (not an I2S signal)
    input logic rst_n
);
    // optional master clock, free running from top; informational only
    logic mclk;

    // agent drive
    logic a_sck     = 1'b1;
    logic a_ws      = 1'b0;
    logic a_clk_oe  = 1'b0;
    logic a_sd      = 1'b0;
    logic a_sd_oe   = 1'b0;

    // other side's drive (top wires the DUT's outputs here)
    logic d_sck;
    logic d_ws;
    logic d_clk_oe;
    logic d_sd;
    logic d_sd_oe;

    // the bus as every device sees it
    logic sck;
    logic ws;
    logic sd;
    assign sck = a_clk_oe ? a_sck : (d_clk_oe === 1'b1) ? d_sck : 1'b1;
    assign ws  = a_clk_oe ? a_ws  : (d_clk_oe === 1'b1) ? d_ws  : 1'b0;
    assign sd  = a_sd_oe  ? a_sd  : (d_sd_oe  === 1'b1) ? d_sd  : 1'b0;
endinterface
