`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_apb_item_pkg::*;
    import odve_apb_agent_pkg::*;
    import odve_apb_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "read_test.sv"
    `include "write_test.sv"
    `include "rw_test.sv"
endpackage

`endif
