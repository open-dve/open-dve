`ifndef ODVE_I2C_SEQ_LIB_PKG
`define ODVE_I2C_SEQ_LIB_PKG
package odve_i2c_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;    // the slave sequencer and the models, for the responding sequence

    `include "odve_i2c_item_seq.sv"
    `include "odve_i2c_rand_seq.sv"
    `include "odve_i2c_slv_model_seq.sv"
endpackage
`endif
