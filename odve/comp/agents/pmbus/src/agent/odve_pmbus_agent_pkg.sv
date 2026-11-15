`ifndef ODVE_PMBUS_AGENT_PKG
`define ODVE_PMBUS_AGENT_PKG
package odve_pmbus_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;
    import odve_smbus_item_pkg::*;
    import odve_smbus_agent_pkg::*;
    import odve_smbus_seq_lib_pkg::*;   // odve_smbus_item_seq: the master driver's transport
    import odve_pmbus_item_pkg::*;

    typedef enum { ODVE_PMBUS_MASTER, ODVE_PMBUS_SLAVE }    odve_pmbus_role_e;
    typedef enum { ODVE_PMBUS_SLV_MEM, ODVE_PMBUS_SLV_SEQ } odve_pmbus_slv_mode_e;

    // the value of a command's data bytes in its format (0.0 for raw data)
    function automatic real odve_pmbus_value(bit [7:0] cmd, bit [7:0] d[$], bit [4:0] vout_exp);
        bit [15:0] v;
        if (d.size() != 2) return 0.0;
        v = {d[1], d[0]};
        case (odve_pmbus_fmt(cmd))
            PMB_FMT_LINEAR11:  return odve_pmbus_lin11_to_real(v);
            PMB_FMT_ULINEAR16: return odve_pmbus_ulin16_to_real(v, vout_exp);
            default:           return 0.0;
        endcase
    endfunction

    // Functional coverage of the PMBus commands (doc/fcov-plan.md 4.1),
    // sampled by the monitor once per command.
    //   cmd     command code       op     0 write, 1 read, 2 send
    //   page    PAGE in effect     pec    a PEC byte was transferred
    //   ack     every byte ACKed   alert  SMBALERT# low at the end
    //   cml     STATUS_CML value read (-1: not a STATUS_CML read)
    //   vbin    value class of LINEAR11/ULINEAR16 data (-1 none, 0 zero, 1 <1, 2 1..2, 3 >2)
`ifdef ODVE_COV_NATIVE
    covergroup odve_pmbus_cg with function sample(int cmd, int op, int page, bit pec, bit ack, bit alert, int cml, int vbin);
        cp_cmd: coverpoint cmd {
            bins page = {0}; bins operation = {1}; bins on_off_config = {2}; bins clear_faults = {3};
            bins capability = {25}; bins vout_mode = {32}; bins vout_command = {33};
            bins status_byte = {120}; bins status_word = {121}; bins status_cml = {126};
            bins read_vout = {139}; bins read_iout = {140}; bins pmbus_revision = {152};
            bins unsupported = {[208:223]};
        }
        cp_paged: coverpoint cmd {
            bins operation = {1}; bins on_off_config = {2}; bins vout_command = {33}; bins status_byte = {120};
            bins status_word = {121}; bins read_vout = {139}; bins read_iout = {140};
        }
        cp_op:    coverpoint op    { bins wr = {0}; bins rd = {1}; bins send = {2}; }
        cp_wr_rd: coverpoint op    { bins wr = {0}; bins rd = {1}; }
        cp_page:  coverpoint page  { bins p0 = {0}; bins p1 = {1}; }
        cp_pec:   coverpoint pec   { bins no = {0}; bins yes = {1}; }
        cp_ack:   coverpoint ack   { bins nack = {0}; bins ack = {1}; }
        cp_alert: coverpoint alert { bins idle = {0}; bins asserted = {1}; }
        cp_cml:   coverpoint cml   { bins clear = {0}; bins cmd_err = {[128:255]}; bins data_err = {[64:127]};
                                     bins pec_err = {[32:63]}; bins other = {2}; }
        cp_vbin:  coverpoint vbin  { bins zero = {0}; bins below_1 = {1}; bins one_to_2 = {2}; bins above_2 = {3}; }
        x_cmd_op: cross cp_cmd, cp_wr_rd {
            ignore_bins ro1 = binsof(cp_cmd.capability) && binsof(cp_wr_rd.wr);
            ignore_bins ro2 = binsof(cp_cmd.read_vout) && binsof(cp_wr_rd.wr);
            ignore_bins ro3 = binsof(cp_cmd.read_iout) && binsof(cp_wr_rd.wr);
            ignore_bins ro4 = binsof(cp_cmd.pmbus_revision) && binsof(cp_wr_rd.wr);
            ignore_bins ro5 = binsof(cp_cmd.status_byte) && binsof(cp_wr_rd.wr);
            ignore_bins ro6 = binsof(cp_cmd.status_word) && binsof(cp_wr_rd.wr);
            ignore_bins cf1 = binsof(cp_cmd.clear_faults) && binsof(cp_wr_rd.wr);
            ignore_bins cf2 = binsof(cp_cmd.clear_faults) && binsof(cp_wr_rd.rd);
            // an unsupported code is NACKed before any Sr: on the bus every such message is a write
            ignore_bins un_rd = binsof(cp_cmd.unsupported) && binsof(cp_wr_rd.rd);
        }
        x_paged_page: cross cp_paged, cp_page;
    endgroup
`endif

    typedef class odve_pmbus_dev_model;
    `include "odve_pmbus_cfg.sv"
    `include "slv/odve_pmbus_dev_model.sv"
    `include "mon/odve_pmbus_mon.sv"
    `include "mst/odve_pmbus_mst_drv.sv"
    `include "odve_pmbus_sqr.sv"
    `include "odve_pmbus_agent.sv"
endpackage
`endif
