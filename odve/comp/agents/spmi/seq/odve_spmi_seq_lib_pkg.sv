`ifndef ODVE_SPMI_SEQ_LIB_PKG
`define ODVE_SPMI_SEQ_LIB_PKG
package odve_spmi_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_spmi_item_pkg::*;
    import odve_spmi_agent_pkg::*;    // the slave sequencer type, for the responding sequence

    `include "odve_spmi_base_seq.sv"
    `include "odve_spmi_dir_seq.sv"
    `include "odve_spmi_slv_mem_seq.sv"
endpackage
`endif
