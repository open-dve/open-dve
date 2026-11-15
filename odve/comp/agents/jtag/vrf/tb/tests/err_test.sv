// The monitor's protocol checks, against a slave agent with a fault
// injected (+jtag_slave=mem|seq):
//   +jtag_err=oe     TDO enabled outside Shift-IR/Shift-DR -> JTAG_OE
//   +jtag_err=ircap  Capture-IR loads 0000 instead of 0001 -> JTAG_IRCAP
//                    (and the scoreboard's IR TDO comparison is switched off)
// The expected errors are demoted to infos by the catcher and counted; the
// test fails unless the monitor reported at least one, and data traffic
// must still check clean.
class err_test extends base_test;
    `uvm_component_utils(err_test)

    function new(string name = "err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        if (env_o.cc_o.err == "oe")    expect_errors("JTAG_OE");
        if (env_o.cc_o.err == "ircap") begin
            expect_errors("JTAG_IRCAP");
            env_o.scb_o.ignore_ir_tdo = 1;
        end
        if (env_o.cc_o.err == "none")
            `uvm_fatal(get_name(), "err_test needs +jtag_err=oe|ircap")
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_jtag_vec_t tdo;
        super.run_phase(phase);
        phase.raise_objection(this);
        ir(ODVE_JTAG_USERDATA);
        dr(odve_jtag_vec_t'(32'h600D_DA7A), 32, tdo, 0, 1, 2);
        dr('0, 32, tdo);
        expect_ok(32'(tdo) == 32'h600D_DA7A, "USERDATA still correct under the injected fault");
        ir(ODVE_JTAG_IDCODE);
        phase.drop_objection(this);
    endtask : run_phase

    virtual function void report_phase(uvm_phase phase);
        int unsigned n = (env_o.cc_o.err == "oe") ? env_o.agt.mon.n_err_oe : env_o.agt.mon.n_err_ircap;
        super.report_phase(phase);
        if (n == 0 || catcher.n_caught != n)
            `uvm_error(get_name(), $sformatf("+jtag_err=%s: monitor reported %0d, catcher demoted %0d - the check did not fire",
                                             env_o.cc_o.err, n, catcher.n_caught))
        else
            `uvm_info(get_name(), $sformatf("+jtag_err=%s: monitor flagged %0d expected violation(s)", env_o.cc_o.err, n), UVM_LOW)
    endfunction
endclass : err_test
