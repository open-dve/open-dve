// SPI bus (Motorola SPI block guide naming: SCK/MOSI/MISO/SS, here sclk/mosi/
// miso/cs_n). One master, up to ODVE_SPI_MAX_CS slaves with one active-low
// chip select each. clk is the TB's system clock: every agent component is
// cycle based (drives with non-blocking assignments at posedge clk, samples
// at posedge clk), the master generates sclk from it.
//
// MISO is shared by all slaves and is not modelled as a tristate net (no
// inout / tri, Verilator's tristate support is limited): every potential
// driver has an explicit value/enable pair - s_miso/s_miso_oe for slave
// agents (one bit per chip select) and d_miso/d_miso_oe for RTL slaves (wired
// from top) - and the bus value is resolved here with plain logic: the
// enabled driver's value, a pull-up (1) when nobody drives. miso_ndrv counts
// the enabled drivers so the monitor can flag contention (> 1) and an
// undriven line (0) at a sampling edge.
`ifndef ODVE_SPI_MAX_CS
`define ODVE_SPI_MAX_CS 4
`endif
interface odve_spi_if (
    input logic clk,
    input logic rst_n
);
    localparam int NCS = `ODVE_SPI_MAX_CS;

    // master
    logic           sclk;
    logic           mosi;
    logic [NCS-1:0] cs_n;
    // slave drivers
    logic [NCS-1:0] s_miso, s_miso_oe;    // slave agent(s), bit i answers cs_n[i]
    logic [NCS-1:0] d_miso, d_miso_oe;    // RTL slave(s), wired from top
    // resolved bus
    logic           miso;
    int unsigned    miso_ndrv;

    assign miso      = (|{s_miso_oe, d_miso_oe}) ? |({s_miso, d_miso} & {s_miso_oe, d_miso_oe}) : 1'b1;
    assign miso_ndrv = $countones({s_miso_oe, d_miso_oe});
endinterface
