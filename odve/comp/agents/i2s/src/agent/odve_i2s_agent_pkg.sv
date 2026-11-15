`ifndef ODVE_I2S_AGENT_PKG
`define ODVE_I2S_AGENT_PKG
package odve_i2s_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2s_item_pkg::*;

    typedef enum { ODVE_I2S_TX, ODVE_I2S_RX }                    odve_i2s_dir_e;       // transmitter / receiver
    typedef enum { ODVE_I2S_CLK_MASTER, ODVE_I2S_CLK_SLAVE }      odve_i2s_clk_role_e;  // controller / target
    typedef enum { ODVE_I2S_SRC_SEQ, ODVE_I2S_SRC_GEN }           odve_i2s_src_e;       // transmitter data source
    typedef enum { ODVE_I2S_INJ_NONE, ODVE_I2S_INJ_WS_GLITCH, ODVE_I2S_INJ_WS_SHIFT } odve_i2s_inj_e;

    // Functional coverage of the frames seen on the bus (doc/fcov-plan.md 4.1),
    // sampled by the monitor once per frame (err = 0, vclass = class of slot 0)
    // and once per protocol violation (err = 1 WS glitch, 2 frame length,
    // vclass = 7, outside every vclass bin).
    //   role: 0 TX controller, 1 TX target, 2 RX controller, 3 RX target
    //   vclass: 0 zero, 1 +full scale, 2 -full scale, 3 positive, 4 negative
`ifdef ODVE_COV_NATIVE
    covergroup odve_i2s_cg with function sample(int fmt, int wlen, int slen, int nslots, bit mono, int role, int vclass, int err);
        cp_fmt:    coverpoint fmt    { bins i2s = {0}; bins lj = {1}; bins rj = {2}; bins tdm = {3}; }
        cp_wlen:   coverpoint wlen   { bins w16 = {16}; bins w24 = {24}; bins w32 = {32}; }
        cp_slen:   coverpoint slen   { bins s16 = {16}; bins s32 = {32}; }
        cp_slots:  coverpoint nslots { bins stereo = {2}; bins tdm4 = {4}; bins tdm8 = {8}; }
        cp_mono:   coverpoint mono   { bins stereo = {0}; bins mono = {1}; }
        cp_role:   coverpoint role   { bins tx_ctrl = {0}; bins tx_tgt = {1}; bins rx_ctrl = {2}; bins rx_tgt = {3}; }
        cp_val:    coverpoint vclass { bins zero = {0}; bins pos_max = {1}; bins neg_min = {2}; bins pos = {3}; bins neg = {4}; }
        cp_err:    coverpoint err    { bins ok = {0}; bins ws_glitch = {1}; bins frame_len = {2}; }
        x_fmt_wlen: cross cp_fmt, cp_wlen;
        x_fmt_role: cross cp_fmt, cp_role;
    endgroup
`endif

    `include "odve_i2s_cfg.sv"
    `include "mon/odve_i2s_mon.sv"
    `include "odve_i2s_drv_base.sv"
    `include "mst/odve_i2s_mst_drv.sv"
    `include "slv/odve_i2s_slv_drv.sv"
    `include "odve_i2s_sqr.sv"
    `include "odve_i2s_agent.sv"
endpackage
`endif
