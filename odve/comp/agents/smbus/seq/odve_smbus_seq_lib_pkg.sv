`ifndef ODVE_SMBUS_SEQ_LIB_PKG
`define ODVE_SMBUS_SEQ_LIB_PKG
package odve_smbus_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;
    import odve_i2c_seq_lib_pkg::*;
    import odve_smbus_item_pkg::*;
    import odve_smbus_agent_pkg::*;

    `include "odve_smbus_item_seq.sv"
    `include "odve_smbus_rand_seq.sv"
    `include "odve_smbus_slv_seq.sv"
endpackage
`endif
