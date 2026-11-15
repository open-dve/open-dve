// Quad SPI (serial NOR flash) bus: cs_n, sclk and four data lines io[3:0]
// (IO0 = DI, IO1 = DO, IO2 = /WP, IO3 = /HOLD in single-line commands).
// clk is the TB's system clock: every agent component is cycle based.
//
// The io lines are bidirectional and are NOT modelled as inout/tri nets
// (Verilator's tristate support is limited). Each driver has an explicit
// value/enable pair per line - m_io/m_io_oe (master agent), s_io/s_io_oe
// (slave agent = behavioural flash), d_io/d_io_oe (RTL flash, wired from
// top) - and the bus is resolved here with plain logic: the enabled
// drivers' value, 1 (the board pull-ups on /WP, /HOLD and DO) when nobody
// drives. io_ndrv[i] counts the drivers enabled on line i so the monitor can
// flag contention (> 1) and an undriven line where data is expected (0).
interface odve_qspi_if (
    input logic clk,
    input logic rst_n
);
    // master
    logic       sclk;
    logic       cs_n;
    logic [3:0] m_io, m_io_oe;
    // slave drivers
    logic [3:0] s_io, s_io_oe;      // slave agent
    logic [3:0] d_io, d_io_oe;      // RTL flash, wired from top
    // resolved bus
    logic [3:0] io;
    logic [1:0] io_ndrv [4];

    for (genvar i = 0; i < 4; i++) begin : g_res
        wire [2:0] oe = {m_io_oe[i], s_io_oe[i], d_io_oe[i]};
        wire [2:0] v  = {m_io[i],    s_io[i],    d_io[i]};
        assign io[i]      = (|oe) ? |(oe & v) : 1'b1;
        assign io_ndrv[i] = 2'(oe[0]) + 2'(oe[1]) + 2'(oe[2]);
    end
endinterface
