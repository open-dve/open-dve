// IDCODE: selected by power-on reset, by Test-Logic-Reset through TMS and
// through TRST_n, and by an explicit IR scan; read as a 32-bit DR (32 per
// TAP in a chain) and checked against the expected value, bit 0 = 1.
class idcode_test extends base_test;
    `uvm_component_utils(idcode_test)

    function new(string name = "idcode_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task read_ids(string after);
        odve_jtag_vec_t tdo;
        dr('0, 32 * n_taps, tdo, 0, 1, 2);
        for (int unsigned k = 0; k < n_taps; k++) begin
            bit [31:0] id = idcode_in(tdo, k);
            expect_ok(id == env_o.cc_o.idcode(k), $sformatf("TAP %0d IDCODE after %s: 0x%08h, expected 0x%08h", k, after, id, env_o.cc_o.idcode(k)));
            expect_ok(id[0] == 1'b1, $sformatf("TAP %0d IDCODE bit 0 is 1", k));
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        read_ids("power-on reset");
        ir_all(ODVE_JTAG_BYPASS);
        reset(0);
        read_ids("TMS reset");
        ir_all(ODVE_JTAG_USERDATA);
        reset(1);
        read_ids("TRST_n reset");
        ir_all(ODVE_JTAG_BYPASS);
        ir_all(ODVE_JTAG_IDCODE, 3);
        read_ids("IR=IDCODE");
        read_ids("IR=IDCODE, second read");
        phase.drop_objection(this);
    endtask : run_phase
endclass : idcode_test
