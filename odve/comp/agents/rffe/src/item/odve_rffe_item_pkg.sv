`ifndef ODVE_RFFE_ITEM_PKG
`define ODVE_RFFE_ITEM_PKG
package odve_rffe_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    // The RFFE command sequences the agent knows (doc/spec.md, "Command
    // sequences"). The numeric values are the coverage encoding of `kind`.
    typedef enum int {
        ODVE_RFFE_REG0_WR = 0,   // 1DDD_DDDD             Register 0 Write (7-bit data in the command frame)
        ODVE_RFFE_REG_WR  = 1,   // 010A_AAAA + 1 data     Register Write (5-bit address)
        ODVE_RFFE_REG_RD  = 2,   // 011A_AAAA + 1 data     Register Read
        ODVE_RFFE_EXT_WR  = 3,   // 0000_BBBB + addr + 1..16 data   Extended Register Write
        ODVE_RFFE_EXT_RD  = 4,   // 0010_BBBB + addr + 1..16 data   Extended Register Read
        ODVE_RFFE_EXTL_WR = 5,   // 0011_0BBB + 2 addr + 1..8 data  Extended Register Write Long
        ODVE_RFFE_EXTL_RD = 6    // 0011_1BBB + 2 addr + 1..8 data  Extended Register Read Long
    } odve_rffe_kind_e;

    `include "odve_rffe_item.sv"
endpackage
`endif
