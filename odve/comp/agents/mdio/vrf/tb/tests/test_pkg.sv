`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_mdio_item_pkg::*;
    import odve_mdio_agent_pkg::*;
    import odve_mdio_seq_lib_pkg::*;
    import env_pkg::*;

    `include "err_catcher.sv"
    `include "base_test.sv"
    `include "c22_test.sv"
    `include "c45_test.sv"
    `include "c45_rinc_test.sv"
    `include "addr_miss_test.sv"
    `include "b2b_test.sv"
    `include "short_pre_test.sv"
    `include "proto_err_test.sv"
    `include "rand_test.sv"
endpackage

`endif
