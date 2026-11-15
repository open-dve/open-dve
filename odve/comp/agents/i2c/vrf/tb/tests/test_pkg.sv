`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;
    import odve_i2c_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "i2c_basic_test.sv"
    `include "i2c_addr10_test.sv"
    `include "i2c_rand_test.sv"
    `include "i2c_nack_test.sv"
    `include "i2c_stretch_test.sv"
    `include "i2c_gencall_test.sv"
    `include "i2c_abort_test.sv"
endpackage

`endif
