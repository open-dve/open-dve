// Pause-IR / Pause-DR: scans that stop in Pause after some bits for 1..5
// TCKs and resume through Exit2 -> Shift. Each scan pauses once, at a
// different point: after the first bit, in the middle, before the last bit
// and after the last bit (Exit2 -> Update). Values must be as if shifted
// without a pause: USERDATA reads back what was written (every TAP of a
// chain gets the same value).
class pause_test extends base_test;
    `uvm_component_utils(pause_test)

    function new(string name = "pause_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_jtag_vec_t tdo, op;
        bit [31:0] prev = 0, v;
        int unsigned len = 32 * n_taps;
        super.run_phase(phase);
        phase.raise_objection(this);
        op = '0;
        for (int unsigned t = 0; t < n_taps; t++) op |= odve_jtag_vec_t'(ODVE_JTAG_USERDATA) << (4 * t);
        ir(op, 0, 2, 3);                          // IR scan paused after 2 bits
        for (int i = 0; i < 6; i++) begin
            int unsigned at = (i == 0) ? 1 : (i == 1) ? 5 : (i == 2) ? 16 : (i == 3) ? len - 1 : (i == 4) ? len : rng.urand(1, len);
            odve_jtag_vec_t tdi = '0;
            v = rng.u32();
            for (int unsigned t = 0; t < n_taps; t++) tdi |= odve_jtag_vec_t'(v) << (32 * t);
            dr(tdi, len, tdo, at, rng.urand(1, 5));
            expect_ok(32'(tdo) == prev, $sformatf("paused at bit %0d: read 0x%08h, expected 0x%08h", at, 32'(tdo), prev));
            prev = v;
        end
        ir(op, 0, 4 * n_taps, 2, 1);              // IR paused after its last bit: Exit2-IR -> Update-IR
        dr('0, len, tdo);
        expect_ok(32'(tdo) == prev, $sformatf("after an IR scan paused at its end: read 0x%08h, expected 0x%08h", 32'(tdo), prev));
        phase.drop_objection(this);
    endtask : run_phase
endclass : pause_test
