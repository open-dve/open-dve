`ifndef __TEST_PKG_SV
`define __TEST_PKG_SV

package test_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_rand_pkg::*;
    import odve_i2s_item_pkg::*;
    import odve_i2s_agent_pkg::*;
    import odve_i2s_seq_lib_pkg::*;
    import env_pkg::*;

    `include "base_test.sv"
    `include "i2s_std_test.sv"
    `include "i2s_lj_test.sv"
    `include "i2s_rj_test.sv"
    `include "i2s_tdm_test.sv"
    `include "i2s_mono_test.sv"
    `include "i2s_corner_test.sv"
    `include "i2s_gap_test.sv"
    `include "i2s_gen_test.sv"
    `include "i2s_ws_err_test.sv"
    `include "i2s_timing_err_test.sv"
endpackage

`endif
