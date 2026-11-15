`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i3c_item_pkg::*;
    import odve_i3c_agent_pkg::*;
    import odve_i3c_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "daa_test.sv"
    `include "priv_test.sv"
    `include "ccc_test.sv"
    `include "parity_test.sv"
    `include "ibi_test.sv"
    `include "setdasa_test.sv"
    `include "hotjoin_test.sv"
endpackage

`endif
