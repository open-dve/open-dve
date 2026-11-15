// Static configuration pins of the DUT, written once by the env at build
// time (tb/env/env.sv) from the test's configuration.
interface dut_cfg_if;
    logic [1:0] fmt;
    logic [5:0] wlen;
    logic       slot32;
    logic [3:0] nslots;
    logic       rx_master;
    logic       tx_master;
    logic [7:0] half;
endinterface
