`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_spmi_item_pkg::*;
    import odve_spmi_agent_pkg::*;
    import odve_spmi_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "reg_test.sv"
    `include "ext_test.sv"
    `include "extl_test.sv"
    `include "boundary_test.sv"
    `include "par_err_test.sv"
    `include "nrf_test.sv"
    `include "pm_test.sv"
    `include "rand_test.sv"
endpackage

`endif
