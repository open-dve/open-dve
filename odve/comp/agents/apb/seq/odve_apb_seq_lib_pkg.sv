`ifndef ODVE_APB_SEQ_LIB_PKG__SV__
`define ODVE_APB_SEQ_LIB_PKG__SV__
package odve_apb_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_apb_item_pkg::*;
    import odve_apb_agent_pkg::*;    // the slave sequencer type, for the responding sequence

    `include "odve_apb_base_seq.sv"
    `include "odve_apb_write_seq.sv"
    `include "odve_apb_read_seq.sv"
    `include "odve_apb_rw_seq.sv"
    `include "odve_apb_slv_mem_seq.sv"
endpackage
`endif
