// MIPI SPMI bus: SCLK (driven by the master only) and SDATA (bidirectional).
//
// SDATA is not modelled as an inout: every driver has its own output and
// output enable here (master agent, slave agent; the DUTs' are wires in top),
// and top resolves the line with plain logic - the enabled driver's value,
// or, when nobody drives, the bus keeper's last value (doc/spec.md,
// "Electrical model"). oe_all collects every enable on the line so the
// monitor can flag contention (more than one enabled driver).
interface odve_spmi_if (
    input logic clk,      // TB clock: SCLK is derived from it, the RTL slaves oversample with it
    input logic rst_n
);
    logic       sclk;        // master -> all
    logic       sdata;       // resolved line (assigned by top)
    // master agent's SDATA driver
    logic       m_sdata_o;
    logic       m_sdata_oe;
    // slave agent's SDATA driver (routed onto the line by top when it plays a slave)
    logic       s_sdata_o;
    logic       s_sdata_oe;
    // every enable on the line, from top: [0] master, [1] slave agent, [2..] RTL slaves
    logic [3:0] oe_all;
endinterface
