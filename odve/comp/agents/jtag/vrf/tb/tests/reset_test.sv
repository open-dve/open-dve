// Test-Logic-Reset from every one of the 16 states: through five TCKs with
// TMS=1 (each state in turn, then random ones) and through TRST_n, also in
// the middle of a DR scan (Shift-DR). After each, the instruction must be
// IDCODE again (the DR read returns the IDCODE); USERDATA must survive a TMS
// reset and be cleared by TRST_n.
class reset_test extends base_test;
    `uvm_component_utils(reset_test)

    function new(string name = "reset_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task expect_idcode(string after);
        odve_jtag_vec_t tdo;
        dr('0, 32 * n_taps, tdo);
        expect_ok(idcode_in(tdo, 0) == env_o.cc_o.idcode(0), $sformatf("IDCODE selected after %s (read 0x%08h)", after, idcode_in(tdo, 0)));
    endtask

    task write_user(bit [31:0] v);
        odve_jtag_vec_t tdo, tdi = '0;
        ir_all(ODVE_JTAG_USERDATA);
        for (int unsigned t = 0; t < n_taps; t++) tdi |= odve_jtag_vec_t'(v) << (32 * t);
        dr(tdi, 32 * n_taps, tdo);
    endtask

    task read_user(output bit [31:0] v);
        odve_jtag_vec_t tdo;
        ir_all(ODVE_JTAG_USERDATA);
        dr('0, 32 * n_taps, tdo);
        v = 32'(tdo);
    endtask

    virtual task run_phase(uvm_phase phase);
        bit [31:0] u;
        super.run_phase(phase);
        phase.raise_objection(this);
        for (int s = 0; s < 16; s++) begin
            ir_all(ODVE_JTAG_BYPASS);
            goto_state(odve_jtag_state_e'(s));
            reset(0, s % 3);
            expect_idcode($sformatf("TMS reset from %s", odve_jtag_state_e'(s)));
        end
        repeat (4) begin
            goto_state(odve_jtag_state_e'(rng.urand(0, 15)));
            reset(1, 1);
            expect_idcode("TRST_n reset");
        end
        // USERDATA: kept by a TMS reset, cleared by TRST_n
        write_user(32'hC0DE_1149);
        reset(0);
        read_user(u);
        expect_ok(u == 32'hC0DE_1149, $sformatf("USERDATA 0x%08h kept over a TMS reset", u));
        write_user(32'h5A5A_A5A5);
        ir_all(ODVE_JTAG_USERDATA);
        goto_state(SH_DR);                     // in the middle of a DR scan ...
        reset(1);                              // ... TRST_n
        read_user(u);
        expect_ok(u == 32'h0, $sformatf("USERDATA 0x%08h cleared by TRST_n during Shift-DR", u));
        phase.drop_objection(this);
    endtask : run_phase
endclass : reset_test
