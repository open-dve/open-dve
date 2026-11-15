`ifndef ODVE_I3C_SEQ_LIB_PKG__SV__
`define ODVE_I3C_SEQ_LIB_PKG__SV__
package odve_i3c_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i3c_item_pkg::*;
    import odve_i3c_agent_pkg::*;    // the target sequencer type, for the responding sequence

    `include "odve_i3c_base_seq.sv"
    `include "odve_i3c_xfer_seq.sv"
    `include "odve_i3c_priv_rand_seq.sv"
    `include "odve_i3c_slv_mem_seq.sv"
endpackage
`endif
