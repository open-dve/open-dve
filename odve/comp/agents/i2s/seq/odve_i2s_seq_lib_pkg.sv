`ifndef ODVE_I2S_SEQ_LIB_PKG__SV__
`define ODVE_I2S_SEQ_LIB_PKG__SV__
package odve_i2s_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2s_item_pkg::*;
    import odve_i2s_agent_pkg::*;

    `include "odve_i2s_base_seq.sv"
    `include "odve_i2s_frame_seq.sv"
    `include "odve_i2s_corner_seq.sv"
    `include "odve_i2s_gap_seq.sv"
endpackage
`endif
