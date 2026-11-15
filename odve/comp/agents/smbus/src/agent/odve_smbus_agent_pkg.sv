`ifndef ODVE_SMBUS_AGENT_PKG
`define ODVE_SMBUS_AGENT_PKG
package odve_smbus_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;
    import odve_i2c_seq_lib_pkg::*;     // odve_i2c_item_seq: the master driver's transport
    import odve_smbus_item_pkg::*;

    typedef enum { ODVE_SMBUS_MASTER, ODVE_SMBUS_SLAVE }    odve_smbus_role_e;
    typedef enum { ODVE_SMBUS_SLV_MEM, ODVE_SMBUS_SLV_SEQ } odve_smbus_slv_mode_e;

    // Functional coverage of the SMBus messages (doc/fcov-plan.md 4.1),
    // sampled by the monitor once per message.
    //   proto    odve_smbus_proto_e     pec/pec_ok  a PEC byte / it matched
    //   ack      every byte ACKed       count       block read byte count
    //   timeout  SCL low >= tTIMEOUT    alert       SMBALERT# low at the end
    //   nw       data bytes written (block write length)
`ifdef ODVE_COV_NATIVE
    covergroup odve_smbus_cg with function sample(int proto, bit pec, bit pec_ok, bit ack, int count, bit timeout, bit alert, int nw);
        cp_proto: coverpoint proto {
            bins quick_w = {0}; bins quick_r = {1}; bins send_byte = {2}; bins recv_byte = {3};
            bins write_byte = {4}; bins read_byte = {5}; bins write_word = {6}; bins read_word = {7};
            bins proc_call = {8}; bins block_write = {9}; bins block_read = {10}; bins block_proc_call = {11};
            bins ara = {12}; bins unknown = {13};
        }
        cp_pec:     coverpoint pec     { bins no = {0}; bins yes = {1}; }
        cp_pec_ok:  coverpoint pec_ok  { bins bad = {0}; bins good = {1}; }
        cp_ack:     coverpoint ack     { bins nack = {0}; bins ack = {1}; }
        cp_count:   coverpoint count   { bins zero = {0}; bins one = {1}; bins mid = {[2:31]}; bins max = {32}; }
        cp_nw:      coverpoint nw      { bins zero = {0}; bins one = {1}; bins two = {2}; bins mid = {[3:31]}; bins max = {32}; }
        cp_timeout: coverpoint timeout { bins none = {0}; bins timeout = {1}; }
        cp_alert:   coverpoint alert   { bins idle = {0}; bins asserted = {1}; }
        x_proto_pec: cross cp_proto, cp_pec {
            ignore_bins quick   = binsof(cp_proto.quick_w) && binsof(cp_pec.yes);
            ignore_bins quick_r = binsof(cp_proto.quick_r) && binsof(cp_pec.yes);
            ignore_bins unk     = binsof(cp_proto.unknown) && binsof(cp_pec.yes);
        }
    endgroup
`endif

    typedef class odve_smbus_dev_model;
    `include "odve_smbus_cfg.sv"
    `include "slv/odve_smbus_dev_model.sv"
    `include "mon/odve_smbus_mon.sv"
    `include "mst/odve_smbus_mst_drv.sv"
    `include "odve_smbus_sqr.sv"
    `include "odve_smbus_agent.sv"
endpackage
`endif
