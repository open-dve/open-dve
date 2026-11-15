`ifndef ODVE_I3C_ITEM_PKG
`define ODVE_I3C_ITEM_PKG
package odve_i3c_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    // What one item is: a controller request (master driver), an observed
    // transfer (monitor), or a request/response between the reactive target
    // driver and its sequence.
    typedef enum int {
        I3C_PRIV_WR = 0,   // private write to a dynamic address
        I3C_PRIV_RD = 1,   // private read
        I3C_CCC_BC  = 2,   // broadcast CCC (7'h7E), optional write payload
        I3C_CCC_DW  = 3,   // direct CCC, write payload (ENEC/DISEC/SETMWL/SETDASA)
        I3C_CCC_DR  = 4,   // direct CCC, read payload (GETxxx)
        I3C_ENTDAA  = 5,   // dynamic address assignment, all rounds
        I3C_IBI     = 6,   // In-Band Interrupt (target-initiated)
        I3C_HOTJOIN = 7    // Hot-Join request (7'h02/W, target-initiated)
    } odve_i3c_kind_e;

    // Common Command Codes modelled (MIPI I3C Basic, SDR)
    localparam bit [7:0] I3C_CCC_ENEC_B    = 8'h00;
    localparam bit [7:0] I3C_CCC_DISEC_B   = 8'h01;
    localparam bit [7:0] I3C_CCC_RSTDAA    = 8'h06;
    localparam bit [7:0] I3C_CCC_ENTDAA    = 8'h07;
    localparam bit [7:0] I3C_CCC_SETMWL_B  = 8'h09;
    localparam bit [7:0] I3C_CCC_ENEC_D    = 8'h80;
    localparam bit [7:0] I3C_CCC_DISEC_D   = 8'h81;
    localparam bit [7:0] I3C_CCC_SETDASA   = 8'h87;
    localparam bit [7:0] I3C_CCC_SETMWL_D  = 8'h89;
    localparam bit [7:0] I3C_CCC_GETMWL    = 8'h8B;
    localparam bit [7:0] I3C_CCC_GETPID    = 8'h8D;
    localparam bit [7:0] I3C_CCC_GETBCR    = 8'h8E;
    localparam bit [7:0] I3C_CCC_GETDCR    = 8'h8F;
    localparam bit [7:0] I3C_CCC_GETSTATUS = 8'h90;

    localparam bit [6:0] I3C_BCAST   = 7'h7E;
    localparam bit [6:0] I3C_HJ_ADDR = 7'h02;

    // ENEC/DISEC event bits
    localparam bit [7:0] I3C_EVT_ENINT = 8'h01;
    localparam bit [7:0] I3C_EVT_ENHJ  = 8'h08;

    // number of payload bytes of a direct GET CCC (0 = not a GET we know)
    function automatic int unsigned i3c_get_len(bit [7:0] ccc);
        case (ccc)
            I3C_CCC_GETPID:    return 6;
            I3C_CCC_GETBCR:    return 1;
            I3C_CCC_GETDCR:    return 1;
            I3C_CCC_GETMWL:    return 2;
            I3C_CCC_GETSTATUS: return 2;
            default:           return 0;
        endcase
    endfunction

    // odd parity bit of a byte (the SDR write T-bit)
    function automatic bit i3c_par8(bit [7:0] b);
        return ~^b;
    endfunction

    `include "odve_i3c_item.sv"
endpackage
`endif
