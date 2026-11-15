// I2C bus: two open-drain lines, SCL and SDA, with a pull-up.
//
// No tristates (Verilator's support is limited): every party that can pull a
// line low has its own *_o / *_oe pair here, and the line is the wired-AND
// of all of them, i.e. a pull-up that any enabled driver with o = 0 pulls
// low:
//   m_*  the agent in master role (controller)
//   s_*  the agent in slave role (target)
//   d_*  the RTL target (DUT), wired from top
//   x_*  a spare pair for a test that needs a third device (bus held low ...)
// Agents write their own pair with non-blocking assignments; top assigns d_*.
interface odve_i2c_if (
    input logic clk,      // the oversampling clock every driver/monitor/DUT acts on
    input logic rst_n
);
    logic m_scl_o = 1'b1, m_scl_oe = 1'b0, m_sda_o = 1'b1, m_sda_oe = 1'b0;
    logic s_scl_o = 1'b1, s_scl_oe = 1'b0, s_sda_o = 1'b1, s_sda_oe = 1'b0;
    logic x_scl_o = 1'b1, x_scl_oe = 1'b0, x_sda_o = 1'b1, x_sda_oe = 1'b0;
    logic d_scl_o, d_scl_oe, d_sda_o, d_sda_oe;      // continuous drivers in top

    // who pulls which line low (for the monitor's ownership checks)
    logic m_scl_pull, m_sda_pull, t_scl_pull, t_sda_pull, x_scl_pull, x_sda_pull;
    assign m_scl_pull = m_scl_oe & ~m_scl_o;
    assign m_sda_pull = m_sda_oe & ~m_sda_o;
    assign t_scl_pull = (s_scl_oe & ~s_scl_o) | (d_scl_oe === 1'b1 & d_scl_o === 1'b0);
    assign t_sda_pull = (s_sda_oe & ~s_sda_o) | (d_sda_oe === 1'b1 & d_sda_o === 1'b0);
    assign x_scl_pull = x_scl_oe & ~x_scl_o;
    assign x_sda_pull = x_sda_oe & ~x_sda_o;

    // the bus: pull-up, wired-AND
    logic scl, sda;
    assign scl = ~(m_scl_pull | t_scl_pull | x_scl_pull);
    assign sda = ~(m_sda_pull | t_sda_pull | x_sda_pull);
endinterface
