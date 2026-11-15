`ifndef ODVE_SPMI_AGENT_PKG
`define ODVE_SPMI_AGENT_PKG
package odve_spmi_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_spmi_item_pkg::*;

    typedef enum { ODVE_SPMI_MASTER, ODVE_SPMI_SLAVE }      odve_spmi_role_e;
    typedef enum { ODVE_SPMI_SLV_MEM, ODVE_SPMI_SLV_SEQ }   odve_spmi_slv_mode_e;   // registers in the driver / in a sequence

    // Power state of an SPMI slave as the PM commands set it; the RTL
    // slave and the slave agent report it in the read-only register at
    // address nregs (0x40).
    typedef enum bit [1:0] { ODVE_SPMI_ACTIVE = 0, ODVE_SPMI_SLEEPING = 1, ODVE_SPMI_SHUTDOWN_ST = 2 } odve_spmi_pm_e;

    // Functional coverage of the bus traffic (doc/fcov-plan.md 4.1), sampled
    // by the monitor once per complete command sequence:
    //   kind     odve_spmi_kind_e
    //   nbytes   data frames (1 for Register 0 Write, 0 for PM commands)
    //   addr_cls 0: 0x00-0x1F, 1: 0x20-0x3F, 2: 0x40 (power state), 3: beyond
    //   par_err  a parity error in any master frame (command, address, data)
    //   ack      the ACK/NACK bit (1 = ACK), counted when has_ack (every non-read command)
    //   nrf      a read data frame came back as a No Response Frame
    //   dir      0 write / PM command, 1 read
`ifdef ODVE_COV_NATIVE
    covergroup odve_spmi_cg with function sample(int kind, int nbytes, int addr_cls, bit par_err, bit ack, bit has_ack, bit nrf, bit dir);
        cp_kind:  coverpoint kind { bins reg0_wr = {0}; bins reg_wr = {1}; bins reg_rd = {2};
                                    bins ext_wr = {3}; bins ext_rd = {4}; bins extl_wr = {5}; bins extl_rd = {6};
                                    bins reset = {7}; bins sleep = {8}; bins shutdown = {9}; bins wakeup = {10}; }
        cp_len:   coverpoint nbytes { bins none = {0}; bins one = {1}; bins few = {[2:7]}; bins eight = {8}; bins many = {[9:15]}; bins sixteen = {16}; }
        cp_addr:  coverpoint addr_cls { bins low = {0}; bins high = {1}; bins pm_state = {2}; bins unimpl = {3}; }
        cp_perr:  coverpoint par_err { bins ok = {0}; bins err = {1}; }
        cp_ack:   coverpoint ack iff (has_ack) { bins nack = {0}; bins ack = {1}; }
        cp_nrf:   coverpoint nrf { bins answered = {0}; bins no_response = {1}; }
        cp_seq:   coverpoint dir { bins wr_then_rd = (0 => 1); bins rd_then_wr = (1 => 0);
                                   bins wr_wr = (0 => 0); bins rd_rd = (1 => 1); }
        x_kind_perr: cross cp_kind, cp_perr;
    endgroup
`endif

    `include "odve_spmi_cfg.sv"
    `include "mon/odve_spmi_mon.sv"
    `include "mst/odve_spmi_mst_drv_base.sv"
    `include "slv/odve_spmi_slv_drv.sv"
    `include "odve_spmi_sqr.sv"
    `include "odve_spmi_slv_sqr.sv"
    `include "odve_spmi_agent.sv"
endpackage
`endif
