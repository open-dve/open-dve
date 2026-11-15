package env_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;
    import odve_smbus_item_pkg::*;
    import odve_smbus_agent_pkg::*;

    parameter bit [6:0]    DEV_ADDR = 7'h3A;   // the device's address: DUT, slave agent, scoreboard
    parameter int unsigned DEV_TMO  = 600;     // its clock-low timeout, cycles (tTIMEOUT 25..35 ms scaled to 500..700)

    `include "cc.sv"
    `include "scb.sv"
    `include "env.sv"
endpackage : env_pkg
