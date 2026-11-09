// APB3 interface: one master, one slave. Bus signals are plain logic inside
// the interface. The master agent's driver writes psel/penable/pwrite/paddr/
// pwdata directly. The slave side has two sources - a DUT wired from top, or
// the slave agent's driver, which writes s_pready/s_prdata/s_pslverr - and
// top decides which one reaches pready/prdata/pslverr (one continuous
// driver per signal, no tristates; see vrf/tb/top.sv).
interface odve_apb_if #(
    parameter int unsigned ADDR_W = 32,
    parameter int unsigned DATA_W = 32
) (
    input logic clk,
    input logic rst_n
);
    // master
    logic              psel;
    logic              penable;
    logic              pwrite;
    logic [ADDR_W-1:0] paddr;
    logic [DATA_W-1:0] pwdata;
    // slave, as seen on the bus
    logic              pready;
    logic [DATA_W-1:0] prdata;
    logic              pslverr;
    // slave agent's drive (routed onto the bus by top when it plays the slave)
    logic              s_pready;
    logic [DATA_W-1:0] s_prdata;
    logic              s_pslverr;
endinterface
