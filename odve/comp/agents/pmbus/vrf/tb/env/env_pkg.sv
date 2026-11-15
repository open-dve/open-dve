package env_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_i2c_item_pkg::*;
    import odve_i2c_agent_pkg::*;
    import odve_smbus_item_pkg::*;
    import odve_smbus_agent_pkg::*;
    import odve_pmbus_item_pkg::*;
    import odve_pmbus_agent_pkg::*;

    parameter bit [6:0]    DEV_ADDR = 7'h40;   // the PMBus device: DUT, slave agent, scoreboard
    parameter int unsigned DEV_TMO  = 600;     // its clock-low timeout (SMBus tTIMEOUT, scaled)

    `include "cc.sv"
    `include "scb.sv"
    `include "env.sv"
endpackage : env_pkg
