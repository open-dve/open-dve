`ifndef ODVE_I2S_ITEM_PKG
`define ODVE_I2S_ITEM_PKG
package odve_i2s_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    // Frame formats (doc/spec.md section 3):
    //   I2S  Philips I2S: WS low = left, MSB one SCK after the WS edge
    //   LJ   left-justified: WS high = left, MSB in the SCK period of the WS edge
    //   RJ   right-justified: WS high = left, LSB in the last SCK period of the slot
    //   TDM  DSP/TDM: one-SCK WS pulse marks the frame, MSB of slot 0 one SCK later
    typedef enum { ODVE_I2S_FMT_I2S, ODVE_I2S_FMT_LJ, ODVE_I2S_FMT_RJ, ODVE_I2S_FMT_TDM } odve_i2s_fmt_e;

    // What user_randomize() puts in a slot
    typedef enum { ODVE_I2S_VAL_RAND, ODVE_I2S_VAL_ZERO, ODVE_I2S_VAL_MAX, ODVE_I2S_VAL_MIN, ODVE_I2S_VAL_SMALL } odve_i2s_val_e;

    localparam int unsigned ODVE_I2S_MAX_SLOTS = 8;

    `include "odve_i2s_item.sv"
endpackage
`endif
