`ifndef ODVE_MDIO_SEQ_LIB_PKG__SV__
`define ODVE_MDIO_SEQ_LIB_PKG__SV__
package odve_mdio_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_mdio_item_pkg::*;
    import odve_mdio_agent_pkg::*;    // the slave sequencer and the PHY model, for the responder

    `include "odve_mdio_base_seq.sv"
    `include "odve_mdio_rand_seq.sv"
    `include "odve_mdio_slv_resp_seq.sv"
endpackage
`endif
