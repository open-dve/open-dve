`ifndef ODVE_SPMI_ITEM_PKG
`define ODVE_SPMI_ITEM_PKG
package odve_spmi_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    // The SPMI command sequences the agent knows (doc/spec.md, "Command
    // sequences"; codes as in Linux include/linux/spmi.h). The numeric values
    // are the coverage encoding of `kind`.
    typedef enum int {
        ODVE_SPMI_REG0_WR  = 0,    // 1DDD_DDDD             Register 0 Write (7-bit data in the command frame)
        ODVE_SPMI_REG_WR   = 1,    // 010A_AAAA + 1 data     Register Write (5-bit address)
        ODVE_SPMI_REG_RD   = 2,    // 011A_AAAA + 1 data     Register Read
        ODVE_SPMI_EXT_WR   = 3,    // 0000_BBBB + addr + 1..16 data   Extended Register Write
        ODVE_SPMI_EXT_RD   = 4,    // 0010_BBBB + addr + 1..16 data   Extended Register Read
        ODVE_SPMI_EXTL_WR  = 5,    // 0011_0BBB + 2 addr + 1..8 data  Extended Register Write Long
        ODVE_SPMI_EXTL_RD  = 6,    // 0011_1BBB + 2 addr + 1..8 data  Extended Register Read Long
        ODVE_SPMI_RESET    = 7,    // 0001_0000             Reset
        ODVE_SPMI_SLEEP    = 8,    // 0001_0001             Sleep
        ODVE_SPMI_SHUTDOWN = 9,    // 0001_0010             Shutdown
        ODVE_SPMI_WAKEUP   = 10    // 0001_0011             Wakeup
    } odve_spmi_kind_e;

    `include "odve_spmi_item.sv"
endpackage
`endif
