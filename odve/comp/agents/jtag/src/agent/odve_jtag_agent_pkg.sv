`ifndef ODVE_JTAG_AGENT_PKG
`define ODVE_JTAG_AGENT_PKG
package odve_jtag_agent_pkg;
    `include "uvm_macros.svh"
    `include "odve_macro.sv"
    import uvm_pkg::*;
    import odve_jtag_item_pkg::*;

    typedef enum { ODVE_JTAG_MASTER, ODVE_JTAG_SLAVE }     odve_jtag_role_e;
    typedef enum { ODVE_JTAG_SLV_MEM, ODVE_JTAG_SLV_SEQ }  odve_jtag_slv_mode_e;   // registers in the driver / in a sequence

    // Instruction set of the modelled TAP (4-bit IR). BYPASS is all ones as
    // the standard requires; every opcode not listed selects BYPASS too.
    localparam bit [3:0] ODVE_JTAG_EXTEST   = 4'h0;
    localparam bit [3:0] ODVE_JTAG_SAMPLE   = 4'h1;   // SAMPLE/PRELOAD
    localparam bit [3:0] ODVE_JTAG_IDCODE   = 4'h2;
    localparam bit [3:0] ODVE_JTAG_USERDATA = 4'h8;
    localparam bit [3:0] ODVE_JTAG_BYPASS   = 4'hF;
    localparam bit [3:0] ODVE_JTAG_IR_CAPTURE = 4'b0001;   // Capture-IR: two LSBs 01

    // Functional coverage (doc/fcov-plan.md 4.1), sampled by the monitor.
    // odve_jtag_cg: one sample per completed operation (reset or scan);
    //   kind 0 reset / 1 IR scan / 2 DR scan, len = scan length, instr = the
    //   instruction in effect (last IR value shifted, first TAP seen from
    //   TDO), npause = pauses in the scan, idle = Run-Test/Idle cycles before
    //   it, trst = reset through TRST_n.
    // odve_jtag_fsm_cg: one sample per rising TCK, the state entered.
`ifdef ODVE_COV_NATIVE
    covergroup odve_jtag_cg with function sample(int kind, int len, int instr, int npause, int idle, int trst);
        cp_kind:  coverpoint kind  { bins reset = {0}; bins ir = {1}; bins dr = {2}; }
        cp_len:   coverpoint len   { bins zero = {0}; bins one = {1}; bins short_ = {2, 3, [5:7]}; bins ir4 = {4};
                                     bins mid = {[8:31]}; bins w32 = {32}; bins w33_64 = {[33:64]}; bins long_ = {[65:$]}; }
        cp_instr: coverpoint instr { bins extest = {0}; bins sample = {1}; bins idcode = {2}; bins user = {8};
                                     bins bypass = {15}; bins unassigned = {[3:7], [9:14]}; }
        cp_pause: coverpoint npause { bins none = {0}; bins paused = {[1:$]}; }   // the master pauses at most once per scan
        cp_idle:  coverpoint idle  { bins b2b = {0}; bins some = {[1:4]}; bins many = {[5:$]}; }
        cp_trst:  coverpoint trst  { bins tms = {0}; bins trst = {1}; }
        x_kind_pause: cross cp_kind, cp_pause { ignore_bins rst = binsof(cp_kind.reset); }
    endgroup

    covergroup odve_jtag_fsm_cg with function sample(int state);
        cp_state: coverpoint state { bins st[] = {[0:15]}; }
        cp_arc:   coverpoint state { bins tlr_rti = (0 => 1); bins sel_dr_ir = (2 => 9); bins sel_ir_tlr = (9 => 0);
                                     bins cap_ex1_dr = (3 => 5); bins cap_ex1_ir = (10 => 12);
                                     bins pause_dr = (5 => 6); bins resume_dr = (7 => 4); bins ex2_upd_dr = (7 => 8);
                                     bins pause_ir = (12 => 13); bins resume_ir = (14 => 11); bins ex2_upd_ir = (14 => 15);
                                     bins upd_dr_sel = (8 => 2); bins upd_ir_sel = (15 => 2); bins upd_dr_rti = (8 => 1); }
    endgroup
`endif

    `include "odve_jtag_tap_model.sv"
    `include "odve_jtag_cfg.sv"
    `include "mon/odve_jtag_mon.sv"
    `include "mst/odve_jtag_mst_drv_base.sv"
    `include "odve_jtag_sqr.sv"
    `include "odve_jtag_slv_sqr.sv"
    `include "slv/odve_jtag_slv_drv.sv"
    `include "odve_jtag_agent.sv"
endpackage
`endif
