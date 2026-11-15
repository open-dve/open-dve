`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_smbus_item_pkg::*;
    import odve_smbus_agent_pkg::*;
    import odve_smbus_seq_lib_pkg::*;
    import odve_pmbus_item_pkg::*;
    import odve_pmbus_agent_pkg::*;
    import odve_pmbus_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "pmbus_basic_test.sv"
    `include "pmbus_page_test.sv"
    `include "pmbus_fault_test.sv"
    `include "pmbus_pec_test.sv"
    `include "pmbus_rand_test.sv"
endpackage

`endif
