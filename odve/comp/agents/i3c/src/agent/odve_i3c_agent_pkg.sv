`ifndef ODVE_I3C_AGENT_PKG
`define ODVE_I3C_AGENT_PKG
package odve_i3c_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_i3c_item_pkg::*;

    typedef enum { ODVE_I3C_MASTER, ODVE_I3C_SLAVE }     odve_i3c_role_e;       // controller / target
    typedef enum { ODVE_I3C_SLV_MEM, ODVE_I3C_SLV_SEQ }  odve_i3c_slv_mode_e;   // registers in the driver / in a sequence

    // Functional coverage of the bus traffic (doc/fcov-plan.md 4.1), sampled
    // by the monitor once per observed transfer. kind = odve_i3c_kind_e,
    // ccc = the CCC code or 256 for a non-CCC transfer, len = payload bytes,
    // t_end only for reads (who ended it), n_perr = wrong write T-bits.
`ifdef ODVE_COV_NATIVE
    covergroup odve_i3c_cg with function sample(int kind, bit ack, int ccc, int len, bit rd, bit t_end, int n_perr);
        cp_kind: coverpoint kind { bins priv_wr = {0}; bins priv_rd = {1}; bins ccc_bc = {2}; bins ccc_dw = {3};
                                   bins ccc_dr = {4}; bins entdaa = {5}; bins ibi = {6}; bins hotjoin = {7}; }
        cp_ack:  coverpoint ack  { bins nack = {0}; bins ack = {1}; }
        cp_ccc:  coverpoint ccc  { bins enec_b = {0}; bins disec_b = {1}; bins rstdaa = {6}; bins entdaa = {7};
                                   bins setmwl_b = {9}; bins enec_d = {128}; bins disec_d = {129}; bins setdasa = {135};
                                   bins setmwl_d = {137}; bins getmwl = {139}; bins getpid = {141}; bins getbcr = {142};
                                   bins getdcr = {143}; bins getstatus = {144}; }
        cp_len:  coverpoint len  { bins zero = {0}; bins one = {1}; bins few = {[2:4]}; bins many = {[5:15]}; bins full = {[16:$]}; }
        cp_tend: coverpoint t_end iff (rd) { bins ctrl_abort = {0}; bins target_end = {1}; }
        cp_perr: coverpoint n_perr { bins none = {0}; bins err = {[1:$]}; }
        x_kind_ack: cross cp_kind, cp_ack {
            ignore_bins bc_nack  = binsof(cp_kind.ccc_bc) && binsof(cp_ack.nack);   // 7E/W: every target ACKs
            ignore_bins daa_nack = binsof(cp_kind.entdaa) && binsof(cp_ack.nack);
        }
    endgroup
`endif

    `include "odve_i3c_cfg.sv"
    `include "mon/odve_i3c_mon.sv"
    `include "mst/odve_i3c_mst_drv_base.sv"
    `include "slv/odve_i3c_slv_drv.sv"
    `include "odve_i3c_sqr.sv"
    `include "odve_i3c_slv_sqr.sv"
    `include "odve_i3c_agent.sv"
endpackage
`endif
