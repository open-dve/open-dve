`ifndef ODVE_UART_AGENT_PKG
`define ODVE_UART_AGENT_PKG
package odve_uart_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_uart_item_pkg::*;

    typedef enum { ODVE_UART_MASTER, ODVE_UART_SLAVE }    odve_uart_role_e;
    typedef enum { ODVE_UART_SLV_MEM, ODVE_UART_SLV_SEQ } odve_uart_slv_mode_e;   // echo FIFO in the driver / responses from a sequence

    // Functional coverage of the characters seen on both lines
    // (doc/fcov-plan.md 4.1), sampled by the monitor through `odve_cov_sample.
    //   dir   0 = txd (master -> peer), 1 = rxd (peer -> master)
    //   nbits 5..8, par odve_uart_parity_e, stop odve_uart_stop_e
    //   err   0 ok, 1 parity, 2 framing, 3 parity + framing, 4 break
    //   dcls  0 all data bits space, 1 all mark, 2 anything else
    //   gap   whole bit times of mark before the start bit (99: first frame)
`ifdef ODVE_COV_NATIVE
    covergroup odve_uart_cg with function sample(int dir, int nbits, int par, int stop, int err, int dcls, int gap);
        cp_dir:  coverpoint dir   { bins tx = {0}; bins rx = {1}; }
        cp_bits: coverpoint nbits { bins b5 = {5}; bins b6 = {6}; bins b7 = {7}; bins b8 = {8}; }
        cp_par:  coverpoint par   { bins none = {0}; bins even = {1}; bins odd = {2}; bins mark = {3}; bins space = {4}; }
        cp_stop: coverpoint stop  { bins s1 = {0}; bins s1_5 = {1}; bins s2 = {2}; }
        cp_err:  coverpoint err   { bins ok = {0}; bins parity = {1}; bins framing = {2}; bins par_fram = {3}; bins brk = {4}; }
        cp_data: coverpoint dcls  { bins zeros = {0}; bins ones = {1}; bins other = {2}; }
        cp_gap:  coverpoint gap   { bins back2back = {0}; bins short_gap = {[1:3]}; bins long_gap = {[4:$]}; }
        x_bits_par:  cross cp_bits, cp_par;
        // 16550 LCR: 1.5 stop bits only with 5 data bits, 2 only with 6..8
        x_bits_stop: cross cp_bits, cp_stop {
            ignore_bins b5_s2   = binsof(cp_bits.b5) && binsof(cp_stop.s2);
            ignore_bins b6_s1_5 = binsof(cp_bits.b6) && binsof(cp_stop.s1_5);
            ignore_bins b7_s1_5 = binsof(cp_bits.b7) && binsof(cp_stop.s1_5);
            ignore_bins b8_s1_5 = binsof(cp_bits.b8) && binsof(cp_stop.s1_5);
        }
        // errors are injected on txd only; the peer never sends a bad frame
        x_dir_err: cross cp_dir, cp_err {
            ignore_bins rx_par  = binsof(cp_dir.rx) && binsof(cp_err.parity);
            ignore_bins rx_fram = binsof(cp_dir.rx) && binsof(cp_err.framing);
            ignore_bins rx_pf   = binsof(cp_dir.rx) && binsof(cp_err.par_fram);
            ignore_bins rx_brk  = binsof(cp_dir.rx) && binsof(cp_err.brk);
        }
    endgroup
`endif

    `include "odve_uart_cfg.sv"
    `include "odve_uart_phy.sv"
    `include "mon/odve_uart_mon.sv"
    `include "mst/odve_uart_mst_drv_base.sv"
    `include "odve_uart_sqr.sv"
    `include "odve_uart_slv_sqr.sv"
    `include "slv/odve_uart_slv_drv.sv"
    `include "odve_uart_agent.sv"
endpackage
`endif
