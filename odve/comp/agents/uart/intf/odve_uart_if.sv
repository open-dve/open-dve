// UART link between the agent (DTE side, "master") and its peer: the RTL
// DUT or the agent in slave role. Every line is a plain push-pull logic
// with one continuous driver (no tristates); lines are named from the
// master agent's point of view and idle (mark) high, RS-232 style at TTL
// level (no inversion).
//
//   txd    master -> peer   serial data (the master driver drives it)
//   rxd    peer   -> master serial data (top routes the DUT's or s_rxd)
//   rts_n  master -> peer   "I can receive", active low (peer's CTS input)
//   cts_n  peer   -> master "you may send", active low (top routes the
//                           DUT's RTS or s_cts_n)
//
// The slave agent drives s_rxd / s_cts_n; top decides which source reaches
// rxd / cts_n (vrf/tb/top.sv, +uart_slave=dut|mem|seq).
interface odve_uart_if (
    input logic clk,
    input logic rst_n
);
    logic txd;
    logic rxd;
    logic rts_n;
    logic cts_n;
    // slave agent's drive
    logic s_rxd;
    logic s_cts_n;
endinterface
