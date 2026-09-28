// APB3 interface: one master, one slave. Signals are plain logic inside the
// interface; the master driver writes psel/penable/pwrite/paddr/pwdata, the
// DUT (slave) is wired to them from top and drives pready/prdata/pslverr.
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
    // slave
    logic              pready;
    logic [DATA_W-1:0] prdata;
    logic              pslverr;
endinterface
