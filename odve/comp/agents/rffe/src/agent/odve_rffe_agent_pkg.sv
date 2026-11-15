`ifndef ODVE_RFFE_AGENT_PKG
`define ODVE_RFFE_AGENT_PKG
package odve_rffe_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rffe_item_pkg::*;

    typedef enum { ODVE_RFFE_MASTER, ODVE_RFFE_SLAVE }      odve_rffe_role_e;
    typedef enum { ODVE_RFFE_SLV_MEM, ODVE_RFFE_SLV_SEQ }   odve_rffe_slv_mode_e;   // registers in the driver / in a sequence

    // Functional coverage of the bus traffic (doc/fcov-plan.md 4.1), sampled
    // by the monitor once per complete command sequence:
    //   kind     odve_rffe_kind_e
    //   nbytes   data frames (1 for Register 0 Write)
    //   addr_cls 0: 0x00-0x1F, 1: 0x20-0x3F, 2: beyond the implemented registers (0x40+)
    //   bcast    command frame addressed to USID 0
    //   par_err  a parity error in any master frame (command, address, data)
    //   nrf      a read data frame came back as a No Response Frame
    //   half     read data clocked at half rate
    //   dir      0 write, 1 read
`ifdef ODVE_COV_NATIVE
    covergroup odve_rffe_cg with function sample(int kind, int nbytes, int addr_cls, bit bcast, bit par_err, bit nrf, bit half, bit dir);
        cp_kind:  coverpoint kind { bins reg0_wr = {0}; bins reg_wr = {1}; bins reg_rd = {2};
                                    bins ext_wr = {3}; bins ext_rd = {4}; bins extl_wr = {5}; bins extl_rd = {6}; }
        cp_len:   coverpoint nbytes { bins one = {1}; bins few = {[2:7]}; bins eight = {8}; bins many = {[9:15]}; bins sixteen = {16}; }
        cp_addr:  coverpoint addr_cls { bins low = {0}; bins high = {1}; bins unimpl = {2}; }
        cp_bcast: coverpoint bcast { bins unicast = {0}; bins broadcast = {1}; }
        cp_perr:  coverpoint par_err { bins ok = {0}; bins err = {1}; }
        cp_nrf:   coverpoint nrf { bins answered = {0}; bins no_response = {1}; }
        cp_half:  coverpoint half { bins full = {0}; bins half_rate = {1}; }
        cp_seq:   coverpoint dir { bins wr_then_rd = (0 => 1); bins rd_then_wr = (1 => 0);
                                   bins wr_wr = (0 => 0); bins rd_rd = (1 => 1); }
        x_kind_perr: cross cp_kind, cp_perr;
    endgroup
`endif

    `include "odve_rffe_cfg.sv"
    `include "mon/odve_rffe_mon.sv"
    `include "mst/odve_rffe_mst_drv_base.sv"
    `include "slv/odve_rffe_slv_drv.sv"
    `include "odve_rffe_sqr.sv"
    `include "odve_rffe_slv_sqr.sv"
    `include "odve_rffe_agent.sv"
endpackage
`endif
