package env_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_spi_item_pkg::*;
    import odve_spi_agent_pkg::*;

    // Functional coverage of the register-protocol traffic the scoreboard
    // checks (doc/fcov-plan.md 4.1): one sample per decoded frame.
    //   rd     1 read / 0 write        cs     chip select
    //   addr   start byte address      nbytes data bytes moved
    //   wrap   the access wrapped from byte 63 to 0
`ifdef ODVE_COV_NATIVE
    covergroup spi_reg_cg with function sample(bit rd, int cs, int addr, int nbytes, bit wrap);
        cp_dir:   coverpoint rd     { bins wr = {0}; bins rd = {1}; }
        cp_cs:    coverpoint cs     { bins sel[] = {[0:1]}; }
        cp_addr:  coverpoint addr   { bins first = {0}; bins low = {[1:31]}; bins high = {[32:62]}; bins last = {63}; }
        cp_len:   coverpoint nbytes { bins cmd_only = {0}; bins short_ = {[1:4]}; bins mid = {[5:16]}; bins long_ = {[17:64]}; bins over = {[65:$]}; }
        cp_wrap:  coverpoint wrap   { bins linear = {0}; bins wrapped = {1}; }
        x_dir_cs:  cross cp_dir, cp_cs;
        x_dir_len: cross cp_dir, cp_len;
    endgroup
`endif

    `include "cc.sv"
    `include "scb.sv"
    `include "env.sv"
endpackage : env_pkg
