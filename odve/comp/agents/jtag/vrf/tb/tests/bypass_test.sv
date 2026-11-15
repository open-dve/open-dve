// BYPASS (all ones) and unassigned opcodes, which must act as BYPASS: DR
// scans of random length come back delayed by one bit per TAP, the first
// bit(s) out being the 0 the bypass register captured.
class bypass_test extends base_test;
    `uvm_component_utils(bypass_test)

    function new(string name = "bypass_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task bypass_scans(string what, int unsigned n);
        odve_jtag_vec_t tdi, tdo, exp;
        int unsigned len;
        repeat (n) begin
            len = rng.urand(1, 64);
            tdi = rng.bits(len);
            dr(tdi, len, tdo);
            exp = tdi << n_taps;
            exp = exp & ((odve_jtag_vec_t'(1) << len) - 1);
            expect_ok(tdo == exp, $sformatf("%s: %0d-bit DR scan through %0d bypass bit(s): tdo 0x%0h, expected 0x%0h", what, len, n_taps, tdo, exp));
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        ir_all(ODVE_JTAG_BYPASS);
        bypass_scans("BYPASS", 8);
        ir_all(4'h3);  bypass_scans("unassigned 0011", 2);
        ir_all(4'h5);  bypass_scans("unassigned 0101", 2);
        ir_all(4'h9);  bypass_scans("unassigned 1001", 2);
        ir_all(4'hE);  bypass_scans("unassigned 1110", 2);
        phase.drop_objection(this);
    endtask : run_phase
endclass : bypass_test
