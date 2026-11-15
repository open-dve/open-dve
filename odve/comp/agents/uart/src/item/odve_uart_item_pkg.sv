`ifndef ODVE_UART_ITEM_PKG
`define ODVE_UART_ITEM_PKG
package odve_uart_item_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_rand_pkg::*;

    typedef enum { ODVE_UART_DATA, ODVE_UART_BREAK, ODVE_UART_GLITCH, ODVE_UART_NONE } odve_uart_kind_e;
    typedef enum { ODVE_UART_TX, ODVE_UART_RX }                                      odve_uart_dir_e;
    typedef enum { ODVE_UART_PAR_NONE, ODVE_UART_PAR_EVEN, ODVE_UART_PAR_ODD,
                   ODVE_UART_PAR_MARK, ODVE_UART_PAR_SPACE }                         odve_uart_parity_e;
    typedef enum { ODVE_UART_STOP1, ODVE_UART_STOP1_5, ODVE_UART_STOP2 }              odve_uart_stop_e;

    // Mask of the data bits of a character of nbits (5..8) bits.
    function automatic bit [7:0] odve_uart_mask(int unsigned nbits);
        return 8'hFF >> (8 - nbits);
    endfunction

    // The parity bit a correct transmitter sends after data (16550 LCR bits
    // 3..5: even/odd parity, stick parity = mark/space).
    function automatic bit odve_uart_parity(bit [7:0] data, int unsigned nbits, odve_uart_parity_e par);
        bit x = ^(data & odve_uart_mask(nbits));
        case (par)
            ODVE_UART_PAR_EVEN:  return x;
            ODVE_UART_PAR_ODD:   return ~x;
            ODVE_UART_PAR_MARK:  return 1'b1;
            default:             return 1'b0;    // SPACE (NONE: not sent)
        endcase
    endfunction

    `include "odve_uart_item.sv"
endpackage
`endif
