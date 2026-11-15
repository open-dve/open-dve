`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_spi_item_pkg::*;
    import odve_spi_agent_pkg::*;
    import odve_spi_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "rw_test.sv"
    `include "mode_test.sv"
    `include "burst_test.sv"
    `include "b2b_test.sv"
    `include "abort_test.sv"
    `include "err_test.sv"
endpackage

`endif
