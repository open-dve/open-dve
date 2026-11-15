// USERDATA read/write: IR=USERDATA, then back-to-back 32-bit DR scans (no
// idle in between); each returns the value the previous one wrote. In a
// chain the other TAP is put in BYPASS and the scan is 33 bits.
class user_test extends base_test;
    `uvm_component_utils(user_test)

    function new(string name = "user_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_jtag_vec_t tdo;
        bit [31:0] prev = 32'h0, v;
        int unsigned len = 32 + (n_taps - 1);
        super.run_phase(phase);
        phase.raise_objection(this);
        // tap[0] (nearest TDI) gets USERDATA, the others BYPASS: the last 4 IR bits go to tap[0]
        if (n_taps == 1) ir(ODVE_JTAG_USERDATA);
        else             ir({ODVE_JTAG_USERDATA, ODVE_JTAG_BYPASS});
        for (int i = 0; i < 12; i++) begin
            v = rng.u32();
            if (i == 10) v = 32'hFFFF_FFFF;
            if (i == 11) v = 32'h0000_0000;
            // tap[0]'s 32 bits are the last ones shifted; the bypass bit is ahead of them
            dr(odve_jtag_vec_t'(v) << (n_taps - 1), len, tdo, 0, 1, (i % 3 == 0) ? 0 : rng.urand(0, 6));
            expect_ok(32'(tdo >> (n_taps - 1)) == prev, $sformatf("USERDATA read 0x%08h, expected 0x%08h", 32'(tdo >> (n_taps - 1)), prev));
            prev = v;
        end
        // the value survives a Test-Logic-Reset through TMS ...
        reset(0);
        if (n_taps == 1) ir(ODVE_JTAG_USERDATA);
        else             ir({ODVE_JTAG_USERDATA, ODVE_JTAG_BYPASS});
        dr('0, len, tdo);
        expect_ok(32'(tdo >> (n_taps - 1)) == prev, $sformatf("USERDATA kept over a TMS reset: 0x%08h", 32'(tdo >> (n_taps - 1))));
        phase.drop_objection(this);
    endtask : run_phase
endclass : user_test
