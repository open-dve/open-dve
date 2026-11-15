// The host operations, one sequence each: reset, goto-state, shift IR,
// shift DR, idle cycles. Set the fields, start() on the master sequencer,
// read tdo / end_state afterwards.

// Test-Logic-Reset: TRST_n pulse (use_trst) or len (>= 5) TCKs with TMS=1, then idle TCKs in RTI.
class odve_jtag_reset_seq extends odve_jtag_base_seq;
    `uvm_object_utils(odve_jtag_reset_seq)
    function new(string name = "odve_jtag_reset_seq");
        super.new(name);
        kind = JTAG_RESET;
        len  = 5;
    endfunction
endclass

// Move the TAP to `target` along the shortest TMS path.
class odve_jtag_goto_seq extends odve_jtag_base_seq;
    `uvm_object_utils(odve_jtag_goto_seq)
    function new(string name = "odve_jtag_goto_seq");
        super.new(name);
        kind = JTAG_GOTO;
    endfunction
endclass

// IR scan of len bits.
class odve_jtag_ir_seq extends odve_jtag_base_seq;
    `uvm_object_utils(odve_jtag_ir_seq)
    function new(string name = "odve_jtag_ir_seq");
        super.new(name);
        kind = JTAG_IR;
        len  = 4;
    endfunction
endclass

// DR scan of len bits.
class odve_jtag_dr_seq extends odve_jtag_base_seq;
    `uvm_object_utils(odve_jtag_dr_seq)
    function new(string name = "odve_jtag_dr_seq");
        super.new(name);
        kind = JTAG_DR;
        len  = 32;
    endfunction
endclass

// len TCKs in Run-Test/Idle.
class odve_jtag_idle_seq extends odve_jtag_base_seq;
    `uvm_object_utils(odve_jtag_idle_seq)
    function new(string name = "odve_jtag_idle_seq");
        super.new(name);
        kind = JTAG_IDLE;
        len  = 1;
    endfunction
endclass
