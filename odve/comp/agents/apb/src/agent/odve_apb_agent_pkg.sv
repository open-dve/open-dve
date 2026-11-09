`ifndef ODVE_APB_AGENT_PKG
`define ODVE_APB_AGENT_PKG
package odve_apb_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_apb_item_pkg::*;

    typedef enum { ODVE_APB_MASTER, ODVE_APB_SLAVE }     odve_apb_role_e;
    typedef enum { ODVE_APB_SLV_MEM, ODVE_APB_SLV_SEQ }  odve_apb_slv_mode_e;   // memory in the driver / in a sequence

    // Functional coverage of the agent's bus traffic (doc/fcov-plan.md 4.1):
    // a real covergroup at package scope, sampled by the monitor through
    // `odve_cov_sample. With FCOV=1 the build turns it into
    // odve_cov_pkg::odve_cov_odve_apb_cg; a tool with covergroup support
    // could compile this block as it is.
`ifdef ODVE_COV_NATIVE
    covergroup odve_apb_cg with function sample(int addr_idx, bit write, bit slverr);
        cp_dir:  coverpoint write  { bins rd = {0}; bins wr = {1}; }
        cp_addr: coverpoint addr_idx { bins reg_[] = {[0:15]}; bins out_of_range = {[16:$]}; }
        cp_err:  coverpoint slverr { bins ok = {0}; bins err = {1}; }
        cp_seq:  coverpoint write  { bins wr_then_rd = (1 => 0); bins rd_then_wr = (0 => 1);
                                     bins wr_wr = (1 => 1); bins rd_rd = (0 => 0); }
        x_dir_err: cross cp_dir, cp_err;
    endgroup
`endif

    `include "odve_apb_cfg.sv"
    `include "mon/odve_apb_mon.sv"
    `include "mst/odve_apb_mst_drv_base.sv"
    `include "slv/odve_apb_slv_drv.sv"
    `include "odve_apb_sqr.sv"
    `include "odve_apb_slv_sqr.sv"
    `include "odve_apb_agent.sv"
endpackage
`endif
