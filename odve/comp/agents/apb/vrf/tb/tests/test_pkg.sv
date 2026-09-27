`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
`ifdef ODVE_FCOV
    import odve_cov_pkg::*;
    `include "odve_cov_apb_cg.sv"
`endif

    `include "read_test.sv"
endpackage  

`endif
