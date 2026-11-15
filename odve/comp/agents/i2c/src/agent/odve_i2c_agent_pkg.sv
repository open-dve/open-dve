`ifndef ODVE_I2C_AGENT_PKG
`define ODVE_I2C_AGENT_PKG
package odve_i2c_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2c_item_pkg::*;

    typedef enum { ODVE_I2C_MASTER, ODVE_I2C_SLAVE }    odve_i2c_role_e;
    typedef enum { ODVE_I2C_SLV_MEM, ODVE_I2C_SLV_SEQ } odve_i2c_slv_mode_e;   // model in the driver / in a sequence

    // Functional coverage of what went over the bus (doc/fcov-plan.md 4.1),
    // sampled by the monitor once per transfer through `odve_cov_sample.
    //   kind     0 write, 1 read, 2 combined write-read (odve_i2c_kind_e)
    //   addr10   10-bit addressing
    //   nwr/nrd  bytes written (register pointer included) / read
    //   addr_ack address acknowledged; wr_nack a written byte was NACKed
    //   special  0 plain, 1 general call, 2 aborted (START/STOP inside a byte)
    //   stretch  a target stretched SCL
`ifdef ODVE_COV_NATIVE
    covergroup odve_i2c_cg with function sample(int kind, bit addr10, int nwr, int nrd, bit addr_ack, bit wr_nack, int special, bit stretch);
        cp_kind:    coverpoint kind     { bins wr = {0}; bins rd = {1}; bins wr_rd = {2}; }
        cp_addr10:  coverpoint addr10   { bins a7 = {0}; bins a10 = {1}; }
        cp_nwr:     coverpoint nwr      { bins none = {0}; bins one = {1}; bins few = {[2:4]}; bins many = {[5:16]}; bins wrap = {[17:$]}; }
        cp_nrd:     coverpoint nrd      { bins none = {0}; bins one = {1}; bins few = {[2:4]}; bins many = {[5:16]}; bins wrap = {[17:$]}; }
        cp_addr_ack: coverpoint addr_ack { bins nack = {0}; bins ack = {1}; }
        cp_wr_nack: coverpoint wr_nack  { bins ok = {0}; bins nack = {1}; }
        cp_special: coverpoint special  { bins plain = {0}; bins gen_call = {1}; bins aborted = {2}; }
        cp_stretch: coverpoint stretch  { bins none = {0}; bins stretched = {1}; }
        cp_seq:     coverpoint kind     { bins wr_then_rd = (0 => 1); bins wr_then_wrrd = (0 => 2); bins rd_rd = (1 => 1); }
        x_kind_addr10: cross cp_kind, cp_addr10;
        x_kind_ack:    cross cp_kind, cp_addr_ack {
            // a NACKed write address ends a combined transfer before its Sr: on the bus it is a write
            ignore_bins wr_rd_nack = binsof(cp_kind.wr_rd) && binsof(cp_addr_ack.nack);
        }
    endgroup
`endif

    typedef class odve_i2c_slv_model;
    `include "odve_i2c_cfg.sv"
    `include "odve_i2c_slv_model.sv"
    `include "mon/odve_i2c_mon.sv"
    `include "mst/odve_i2c_mst_drv_base.sv"
    `include "slv/odve_i2c_slv_drv.sv"
    `include "odve_i2c_sqr.sv"
    `include "odve_i2c_slv_sqr.sv"
    `include "odve_i2c_agent.sv"
endpackage
`endif
