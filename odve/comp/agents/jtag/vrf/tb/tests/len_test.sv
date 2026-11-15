// Arbitrary scan lengths: IR scans of 0..9 bits (an IR scan of other than
// 4 bits per TAP leaves whatever the shift register holds), then USERDATA
// DR scans of 0, 1, 2, 31, 32, 33, 64, 100 and ODVE_JTAG_MAX_LEN-1 bits:
// shorter than the register keeps part of the captured value, longer
// passes TDI through to TDO after the register's own bits. The scoreboard
// checks every bit.
class len_test extends base_test;
    `uvm_component_utils(len_test)

    function new(string name = "len_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_jtag_vec_t tdo;
        int unsigned lens [] = '{0, 1, 2, 31, 32, 33, 64, 100, ODVE_JTAG_MAX_LEN - 1};
        super.run_phase(phase);
        phase.raise_objection(this);
        for (int unsigned l = 0; l <= 9; l++) begin
            ir(odve_jtag_vec_t'(rng.u32()), l);
            dr(odve_jtag_vec_t'(rng.u32()), 8, tdo);
        end
        ir_all(ODVE_JTAG_USERDATA);
        foreach (lens[i]) dr(rng.bits(lens[i]), lens[i], tdo, 0, 1, i % 2);
        phase.drop_objection(this);
    endtask : run_phase
endclass : len_test
