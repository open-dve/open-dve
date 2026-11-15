// EXTEST and SAMPLE/PRELOAD are present: both select the 8-bit boundary
// register, which captures the TAP's pins (8'hA5 + TAP index) and latches
// the shifted value at Update (PRELOAD, then EXTEST drives it on pins_o).
// Every TAP of a chain gets the same instruction; the scan is 8 bits per TAP.
class bsr_test extends base_test;
    `uvm_component_utils(bsr_test)

    function new(string name = "bsr_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_jtag_vec_t tdo;
        int unsigned len = 8 * n_taps;
        super.run_phase(phase);
        phase.raise_objection(this);
        ir_all(ODVE_JTAG_SAMPLE, 1);
        dr(rng.bits(len), len, tdo);                       // SAMPLE captures the pins, PRELOAD the shifted value
        for (int unsigned k = 0; k < n_taps; k++) begin
            bit [7:0] got = 8'(tdo >> (8 * (n_taps - 1 - k)));
            expect_ok(got == env_o.cc_o.pins(k), $sformatf("SAMPLE TAP %0d captured 0x%02h, expected pins 0x%02h", k, got, env_o.cc_o.pins(k)));
        end
        dr(rng.bits(len), len, tdo, 3, 2);
        ir_all(ODVE_JTAG_EXTEST, 2);
        repeat (4) dr(rng.bits(len), len, tdo, 0, 1, rng.urand(0, 3));
        for (int unsigned k = 0; k < n_taps; k++) begin
            bit [7:0] got = 8'(tdo >> (8 * (n_taps - 1 - k)));
            expect_ok(got == env_o.cc_o.pins(k), $sformatf("EXTEST TAP %0d captured 0x%02h, expected pins 0x%02h", k, got, env_o.cc_o.pins(k)));
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : bsr_test
