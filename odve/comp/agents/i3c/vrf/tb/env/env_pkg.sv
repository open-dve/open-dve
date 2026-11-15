package env_pkg;
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import odve_i3c_item_pkg::*;
    import odve_i3c_agent_pkg::*;

    // Identity of the two targets of this testbench. top.sv builds the RTL
    // target with the DUT_* values, env.sv configures the target agent with
    // the TGT_* ones, and the scoreboard models both.
    localparam bit [47:0] DUT_PID = 48'h14B4_C3D0_1000;
    localparam bit [7:0]  DUT_BCR = 8'h06;      // IBI capable, with Mandatory Data Byte
    localparam bit [7:0]  DUT_DCR = 8'h44;
    localparam bit [6:0]  DUT_SA  = 7'h50;      // static address (SETDASA)
    localparam bit [47:0] TGT_PID = 48'h14B4_0001_7000;   // lower: wins the first ENTDAA round
    localparam bit [7:0]  TGT_BCR = 8'h02;      // IBI capable, no payload
    localparam bit [7:0]  TGT_DCR = 8'h00;
    localparam bit [6:0]  TGT_SA  = 7'h51;
    localparam int        NREGS   = 16;

    `include "cc.sv"
    `include "scb.sv"
    `include "env.sv"
endpackage : env_pkg
