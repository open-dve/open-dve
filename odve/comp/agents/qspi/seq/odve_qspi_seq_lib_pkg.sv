`ifndef ODVE_QSPI_SEQ_LIB_PKG__SV__
`define ODVE_QSPI_SEQ_LIB_PKG__SV__
package odve_qspi_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_qspi_item_pkg::*;
    import odve_qspi_agent_pkg::*;

    `include "odve_qspi_base_seq.sv"
    `include "odve_qspi_rand_seq.sv"
    `include "odve_qspi_slv_rsp_seq.sv"
endpackage
`endif
