`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_jtag_item_pkg::*;
    import odve_jtag_agent_pkg::*;
    import odve_jtag_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "idcode_test.sv"
    `include "bypass_test.sv"
    `include "user_test.sv"
    `include "len_test.sv"
    `include "pause_test.sv"
    `include "reset_test.sv"
    `include "bsr_test.sv"
    `include "goto_test.sv"
    `include "rand_test.sv"
    `include "chain_test.sv"
    `include "err_test.sv"
endpackage

`endif
