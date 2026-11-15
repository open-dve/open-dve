// IEEE 1149.1 test access port, one host (the master agent) and one target
// side. Every line is plain logic with exactly one continuous driver:
//   tck, tms, tdi, trst_n   written by the master agent's driver
//   tdo, tdo_oe             the target side as seen on the bus; top.sv
//                           selects the RTL DUT (single TAP or a chain of
//                           two) or the slave agent's s_tdo/s_tdo_oe
// TDO is a 3-state output in the standard; here its enable is an explicit
// signal (tdo_oe) and top resolves the line to 1 (pull-up) when no target
// drives it, so no inout/tri resolution is needed on either simulator.
// clk/rst_n are the testbench's system clock and power-on reset: the master
// derives TCK from clk (cfg.tck_half clk cycles per TCK phase).
interface odve_jtag_if (
    input logic clk,
    input logic rst_n
);
    // host -> target
    logic       tck;
    logic       tms;
    logic       tdi;
    logic       trst_n;      // optional TAP reset, active low, asynchronous
    // target -> host, as seen on the bus
    logic       tdo;
    logic       tdo_oe;      // 1 while the target shifts (Shift-IR/Shift-DR)
    // slave agent's drive (routed onto the bus by top when it plays the target)
    logic       s_tdo;
    logic       s_tdo_oe;
    // debug: the TAP state of the RTL target (first TAP), for goto checks only
    logic [3:0] dbg_state;
endinterface
