`ifndef ODVE_PMBUS_SEQ_LIB_PKG
`define ODVE_PMBUS_SEQ_LIB_PKG
package odve_pmbus_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_smbus_item_pkg::*;
    import odve_smbus_agent_pkg::*;
    import odve_smbus_seq_lib_pkg::*;
    import odve_pmbus_item_pkg::*;
    import odve_pmbus_agent_pkg::*;

    `include "odve_pmbus_item_seq.sv"
    `include "odve_pmbus_rand_seq.sv"
    `include "odve_pmbus_slv_seq.sv"
endpackage
`endif
