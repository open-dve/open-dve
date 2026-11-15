`ifndef ODVE_JTAG_ITEM_PKG
`define ODVE_JTAG_ITEM_PKG
package odve_jtag_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

`ifndef ODVE_JTAG_MAX_LEN
`define ODVE_JTAG_MAX_LEN 256
`endif
    localparam int unsigned ODVE_JTAG_MAX_LEN = `ODVE_JTAG_MAX_LEN;
    typedef bit [ODVE_JTAG_MAX_LEN-1:0] odve_jtag_vec_t;   // bit 0 = first bit shifted

    // The 16 TAP controller states (IEEE 1149.1). The numbering is this
    // agent's own; the RTL DUT uses the same so the debug port compares.
    typedef enum bit [3:0] {
        TLR    = 4'd0,  RTI    = 4'd1,
        SEL_DR = 4'd2,  CAP_DR = 4'd3,  SH_DR = 4'd4,  EX1_DR = 4'd5,
        PA_DR  = 4'd6,  EX2_DR = 4'd7,  UPD_DR = 4'd8,
        SEL_IR = 4'd9,  CAP_IR = 4'd10, SH_IR = 4'd11, EX1_IR = 4'd12,
        PA_IR  = 4'd13, EX2_IR = 4'd14, UPD_IR = 4'd15
    } odve_jtag_state_e;

    // Next state at a rising TCK edge, from the TMS level sampled there.
    function automatic odve_jtag_state_e odve_jtag_next(odve_jtag_state_e s, bit tms);
        case (s)
            TLR:    return tms ? TLR    : RTI;
            RTI:    return tms ? SEL_DR : RTI;
            SEL_DR: return tms ? SEL_IR : CAP_DR;
            CAP_DR: return tms ? EX1_DR : SH_DR;
            SH_DR:  return tms ? EX1_DR : SH_DR;
            EX1_DR: return tms ? UPD_DR : PA_DR;
            PA_DR:  return tms ? EX2_DR : PA_DR;
            EX2_DR: return tms ? UPD_DR : SH_DR;
            UPD_DR: return tms ? SEL_DR : RTI;
            SEL_IR: return tms ? TLR    : CAP_IR;
            CAP_IR: return tms ? EX1_IR : SH_IR;
            SH_IR:  return tms ? EX1_IR : SH_IR;
            EX1_IR: return tms ? UPD_IR : PA_IR;
            PA_IR:  return tms ? EX2_IR : PA_IR;
            EX2_IR: return tms ? UPD_IR : SH_IR;
            default: return tms ? SEL_DR : RTI;   // UPD_IR
        endcase
    endfunction

    function automatic bit odve_jtag_is_shift(odve_jtag_state_e s);
        return s == SH_DR || s == SH_IR;
    endfunction

    typedef enum int { JTAG_RESET, JTAG_IR, JTAG_DR, JTAG_IDLE, JTAG_GOTO } odve_jtag_kind_e;

    `include "odve_jtag_item.sv"
endpackage
`endif
