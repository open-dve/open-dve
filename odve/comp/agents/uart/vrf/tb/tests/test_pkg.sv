`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_uart_item_pkg::*;
    import odve_uart_agent_pkg::*;
    import odve_uart_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "basic_test.sv"
    `include "format_test.sv"
    `include "b2b_test.sv"
    `include "baud_test.sv"
    `include "err_test.sv"
    `include "overrun_test.sv"
    `include "flow_test.sv"
endpackage

`endif
