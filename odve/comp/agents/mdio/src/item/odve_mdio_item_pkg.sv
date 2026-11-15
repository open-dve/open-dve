`ifndef ODVE_MDIO_ITEM_PKG
`define ODVE_MDIO_ITEM_PKG
package odve_mdio_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    // Frame kinds. The ST/OP encodings are in odve_mdio_item::st()/op().
    typedef enum int {
        ODVE_MDIO_C22_WR   = 0,   // ST=01 OP=01
        ODVE_MDIO_C22_RD   = 1,   // ST=01 OP=10
        ODVE_MDIO_C45_ADDR = 2,   // ST=00 OP=00
        ODVE_MDIO_C45_WR   = 3,   // ST=00 OP=01
        ODVE_MDIO_C45_RD   = 4,   // ST=00 OP=11
        ODVE_MDIO_C45_RINC = 5,   // ST=00 OP=10 post-read-increment-address
        ODVE_MDIO_C22_BAD  = 6    // ST=01 with OP=00/11 (undefined): error injection
    } odve_mdio_kind_e;

    `include "odve_mdio_item.sv"
endpackage
`endif
