`ifndef ODVE_RFFE_SEQ_LIB_PKG
`define ODVE_RFFE_SEQ_LIB_PKG
package odve_rffe_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_rffe_item_pkg::*;
    import odve_rffe_agent_pkg::*;    // the slave sequencer type, for the responding sequence

    `include "odve_rffe_base_seq.sv"
    `include "odve_rffe_dir_seq.sv"
    `include "odve_rffe_slv_mem_seq.sv"
endpackage
`endif
