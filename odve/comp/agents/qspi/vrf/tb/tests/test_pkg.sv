`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_qspi_item_pkg::*;
    import odve_qspi_agent_pkg::*;
    import odve_qspi_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "id_test.sv"
    `include "read_test.sv"
    `include "prog_test.sv"
    `include "busy_test.sv"
    `include "rand_test.sv"
    `include "err_test.sv"
endpackage

`endif
