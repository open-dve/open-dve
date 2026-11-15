`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;
    import odve_smbus_item_pkg::*;
    import odve_smbus_agent_pkg::*;
    import odve_smbus_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "smbus_proto_test.sv"
    `include "smbus_rand_test.sv"
    `include "smbus_pec_test.sv"
    `include "smbus_alert_test.sv"
    `include "smbus_timeout_test.sv"
    `include "smbus_err_test.sv"
endpackage

`endif
