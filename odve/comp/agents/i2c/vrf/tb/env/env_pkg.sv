package env_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;

    // the target's addresses: DUT parameters, slave agent cfg, scoreboard
    parameter bit [6:0] TGT_ADDR7  = 7'h50;
    parameter bit [9:0] TGT_ADDR10 = 10'h2A5;

    `include "cc.sv"
    `include "scb.sv"
    `include "env.sv"
endpackage : env_pkg
