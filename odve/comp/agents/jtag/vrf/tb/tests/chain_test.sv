// Daisy chain of two TAPs (+jtag_slave=chain): an 8-bit IR scan sets both
// instructions (the first 4 bits shifted reach the TAP nearest TDO), DR
// lengths are the sum of the selected registers:
//   IDCODE + IDCODE    64 bits, both IDs
//   BYPASS + BYPASS    2-bit delay
//   USERDATA + BYPASS  33 bits, read/write tap[0]'s register through tap[1]'s bypass
//   BYPASS + USERDATA  33 bits, the other way round
// Runs on a single target too (then only the first TAP's half is meaningful
// and the scoreboard still checks every bit).
class chain_test extends base_test;
    `uvm_component_utils(chain_test)

    function new(string name = "chain_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_jtag_vec_t tdo, irtdo;
        super.run_phase(phase);
        phase.raise_objection(this);
        if (n_taps != 2) `uvm_fatal(get_name(), "chain_test needs +jtag_slave=chain")
        // IR capture of the chain: 0001 from each TAP
        ir_rd({ODVE_JTAG_IDCODE, ODVE_JTAG_IDCODE}, irtdo);
        expect_ok(8'(irtdo) == 8'h11, $sformatf("chain IR capture 0x%02h, expected 0x11", 8'(irtdo)));
        dr('0, 64, tdo);
        expect_ok(idcode_in(tdo, 0) == env_o.cc_o.idcode(0) && idcode_in(tdo, 1) == env_o.cc_o.idcode(1),
              $sformatf("chain IDCODEs 0x%08h 0x%08h", idcode_in(tdo, 0), idcode_in(tdo, 1)));
        ir({ODVE_JTAG_BYPASS, ODVE_JTAG_BYPASS});
        dr(odve_jtag_vec_t'(16'hBEEF), 18, tdo);
        expect_ok(18'(tdo) == 18'(32'hBEEF << 2), $sformatf("2-bit bypass delay: 0x%0h", 18'(tdo)));
        // tap[0] USERDATA, tap[1] BYPASS
        ir({ODVE_JTAG_USERDATA, ODVE_JTAG_BYPASS});
        dr(odve_jtag_vec_t'(32'hCAFE_F00D) << 1, 33, tdo);
        dr(odve_jtag_vec_t'(32'h1234_ABCD) << 1, 33, tdo, 17, 2);
        expect_ok(32'(tdo >> 1) == 32'hCAFE_F00D, $sformatf("tap[0] USERDATA 0x%08h", 32'(tdo >> 1)));
        // tap[0] BYPASS, tap[1] USERDATA: tap[1]'s 32 bits are shifted first
        ir({ODVE_JTAG_BYPASS, ODVE_JTAG_USERDATA});
        dr(odve_jtag_vec_t'(32'h0BAD_BEEF), 33, tdo);
        dr('0, 33, tdo);
        expect_ok(32'(tdo) == 32'h0BAD_BEEF, $sformatf("tap[1] USERDATA 0x%08h", 32'(tdo)));
        // and tap[0] still holds its value
        ir({ODVE_JTAG_USERDATA, ODVE_JTAG_BYPASS});
        dr('0, 33, tdo);
        expect_ok(32'(tdo >> 1) == 32'h1234_ABCD, $sformatf("tap[0] USERDATA kept 0x%08h", 32'(tdo >> 1)));
        phase.drop_objection(this);
    endtask : run_phase
endclass : chain_test
