`ifndef ODVE_I2C_ITEM_PKG
`define ODVE_I2C_ITEM_PKG
package odve_i2c_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    // One controller transfer, START .. STOP:
    //   I2C_WRITE       S addr+W data* P
    //   I2C_READ        S addr+R data* P            (10-bit: S hdr+W a[7:0] Sr hdr+R data* P)
    //   I2C_WRITE_READ  S addr+W data* Sr addr+R data* P (combined format)
    typedef enum int { I2C_WRITE = 0, I2C_READ = 1, I2C_WRITE_READ = 2 } odve_i2c_kind_e;

    // Target-side events of the reactive slave (one response each).
    typedef enum int { I2C_EV_ADDR = 0, I2C_EV_WRITE = 1, I2C_EV_READ = 2, I2C_EV_STOP = 3 } odve_i2c_ev_e;

    `include "odve_i2c_item.sv"
    `include "odve_i2c_slv_item.sv"
endpackage
`endif
