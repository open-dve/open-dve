`ifndef ODVE_UART_SEQ_LIB_PKG__SV__
`define ODVE_UART_SEQ_LIB_PKG__SV__
package odve_uart_seq_lib_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_uart_item_pkg::*;
    import odve_uart_agent_pkg::*;

    `include "odve_uart_base_seq.sv"
    `include "odve_uart_pattern_seq.sv"
    `include "odve_uart_slv_echo_seq.sv"
endpackage
`endif
