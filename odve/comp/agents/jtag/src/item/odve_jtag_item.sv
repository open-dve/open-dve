// One JTAG operation. As a master request:
//   JTAG_RESET  Test-Logic-Reset: TRST_n pulse (use_trst) or len (>= 5) TCKs with TMS=1
//   JTAG_IR     IR scan of len bits (tdi, bit 0 first), tdo returned
//   JTAG_DR     DR scan of len bits, the same way
//   JTAG_IDLE   len TCKs in Run-Test/Idle
//   JTAG_GOTO   move the TAP to state `target` along the shortest TMS path
// Scans may stop in Pause-xR after pause_at bits for pause_cycles TCKs and
// resume through Exit2-xR (pause_at == len: Exit2 -> Update). Every
// operation but GOTO ends with idle TCKs in Run-Test/Idle.
// As seen by the monitor: kind RESET/IR/DR, len/tdi/tdo of the scan (tdo =
// the captured value shifted out, tdi = what Update latched), n_pause, the
// Run-Test/Idle cycles seen before it in idle, via_trst for a reset.
// As a slave-sequence request (reactive TAP, SLV_SEQ): kind JTAG_DR with
// instr = the current instruction, is_update = 0 at Capture-DR (answer: len
// and tdi = the captured value) or 1 at Update-DR (tdi = the shifted value).
// No `rand`/constraints (comp/agents/README.md): user_randomize() draws from
// the odve_rand stream in rng, set by the sequence.
class odve_jtag_item extends uvm_sequence_item;
    `uvm_object_utils(odve_jtag_item)

    odve_jtag_kind_e  kind         = JTAG_IDLE;
    int unsigned      len          = 0;
    odve_jtag_vec_t   tdi          = '0;
    odve_jtag_vec_t   tdo          = '0;
    bit               use_trst     = 0;
    int unsigned      pause_at     = 0;     // 0 = no pause
    int unsigned      pause_cycles = 1;
    int unsigned      idle         = 0;
    odve_jtag_state_e target       = RTI;
    // observed
    bit               via_trst     = 0;
    int unsigned      n_pause      = 0;
    odve_jtag_state_e end_state    = RTI;
    // slave-sequence request/response
    int unsigned      instr        = 0;
    bit               is_update    = 0;

    // knobs of user_randomize()
    odve_rand         rng;
    int unsigned      ir_len       = 4;     // total IR length of the chain
    int unsigned      max_dr_len   = 80;

    function new(string name = "odve_jtag_item");
        super.new(name);
    endfunction

    // A random operation: mostly scans, sometimes a reset or idle cycles.
    function void user_randomize();
        int unsigned k;
        int unsigned w[];
        if (rng == null) rng = new(get_full_name());
        w = new[4];
        w[0] = 8; w[1] = 30; w[2] = 52; w[3] = 10;     // reset, IR, DR, idle
        k = rng.weighted(w);
        case (k)
            0: kind = JTAG_RESET;
            1: kind = JTAG_IR;
            2: kind = JTAG_DR;
            default: kind = JTAG_IDLE;
        endcase
        use_trst = 0;
        pause_at = 0;
        pause_cycles = 1;
        tdi = '0;
        case (kind)
            JTAG_RESET: begin use_trst = rng.chance(50); len = 5; end
            JTAG_IR:    len = ir_len;
            JTAG_DR:    len = rng.urand(0, max_dr_len);
            default:    len = rng.urand(1, 6);
        endcase
        if (kind inside {JTAG_IR, JTAG_DR}) begin
            tdi = rng.bits(len);
            if (len > 0 && rng.chance(25)) begin
                pause_at     = rng.urand(1, len);
                pause_cycles = rng.urand(1, 4);
            end
        end
        idle = rng.urand(0, 3);
    endfunction

    function string convert2string();
        case (kind)
            JTAG_RESET: return $sformatf("RESET %s", (use_trst || via_trst) ? "TRST_n" : "TMS");
            JTAG_IDLE:  return $sformatf("IDLE %0d", len);
            JTAG_GOTO:  return $sformatf("GOTO %s", target.name());
            default:    return $sformatf("%s len=%0d tdi=0x%0h tdo=0x%0h pause=%0d idle=%0d",
                                         kind == JTAG_IR ? "IR" : "DR", len, tdi, tdo, n_pause, idle);
        endcase
    endfunction
endclass
