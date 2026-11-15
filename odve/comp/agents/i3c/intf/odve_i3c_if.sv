// I3C SDR bus: SCL + SDA, one controller and up to two targets on it.
//
// No inout/tri/wand: every driver of SDA has its own output enable and value
// (one set per agent role and one for the RTL DUT target), and the bus value
// is resolved below with plain logic, which every simulator (Verilator
// included) evaluates the same way.
//
//   x_sda_oe x_sda_o   meaning
//      0        -      released (open-drain high / high-Z)
//      1        0      drives low  (open-drain pull or push-pull 0)
//      1        1      drives high (push-pull only)
//   x_sda_pp           1 while the driver is in push-pull mode (informative:
//                      a driver never drives high in open-drain mode)
//
// The bus has a pull-up (in I3C: the controller's high-keeper): SDA is 1
// unless somebody drives it low. `contention` is a push-pull high fighting a
// low from another driver; the monitor flags it.
//
// SCL is push-pull from the controller only (I3C SDR has no clock
// stretching).
interface odve_i3c_if (
    input logic clk,
    input logic rst_n
);
    // resolved bus
    logic scl;
    logic sda;

    // controller (agent, master role)
    logic m_scl_o  = 1'b1;
    logic m_sda_oe = 1'b0;
    logic m_sda_o  = 1'b0;
    logic m_sda_pp = 1'b0;

    // target (agent, slave role) - stays released when no target agent is built
    logic t_sda_oe = 1'b0;
    logic t_sda_o  = 1'b0;
    logic t_sda_pp = 1'b0;

    // target (RTL DUT) - assigned from top
    logic d_sda_oe;
    logic d_sda_o;
    logic d_sda_pp;

    // DUT side band, driven by the testbench: a pulse on d_ibi_req queues one
    // In-Band Interrupt carrying d_ibi_mdb
    logic       d_ibi_req = 1'b0;
    logic [7:0] d_ibi_mdb = 8'h00;

    logic pull_low;
    logic drive_hi;
    logic contention;

    assign pull_low   = (m_sda_oe & ~m_sda_o) | (t_sda_oe & ~t_sda_o) | (d_sda_oe & ~d_sda_o);
    assign drive_hi   = (m_sda_oe &  m_sda_o) | (t_sda_oe &  t_sda_o) | (d_sda_oe &  d_sda_o);
    assign contention = pull_low & drive_hi;
    assign sda        = ~pull_low;
    assign scl        = m_scl_o;
endinterface
