`ifndef ODVE_JTAG_SEQ_LIB_PKG__SV__
`define ODVE_JTAG_SEQ_LIB_PKG__SV__
package odve_jtag_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_jtag_item_pkg::*;
    import odve_jtag_agent_pkg::*;    // instruction codes, the slave sequencer and the TAP model

    `include "odve_jtag_base_seq.sv"
    `include "odve_jtag_ops_seq.sv"
    `include "odve_jtag_rand_seq.sv"
    `include "odve_jtag_slv_reg_seq.sv"
endpackage
`endif
