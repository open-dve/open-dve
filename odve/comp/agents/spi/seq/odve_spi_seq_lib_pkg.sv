`ifndef ODVE_SPI_SEQ_LIB_PKG__SV__
`define ODVE_SPI_SEQ_LIB_PKG__SV__
package odve_spi_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_spi_item_pkg::*;
    import odve_spi_agent_pkg::*;

    `include "odve_spi_base_seq.sv"
    `include "odve_spi_reg_seq.sv"
    `include "odve_spi_raw_seq.sv"
    `include "odve_spi_slv_rsp_seq.sv"
endpackage
`endif
