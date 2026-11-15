// The goto-state operation and the monitor's TAP tracking: the host walks
// to every one of the 16 states in turn and then to 40 random ones; after
// each move the master driver's own copy, the monitor's and (with an RTL
// target) the DUT's TAP state must all be the target.
class goto_test extends base_test;
    `uvm_component_utils(goto_test)

    function new(string name = "goto_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task go_check(odve_jtag_state_e t);
        goto_state(t);
        #1;    // let the rising TCK edge settle in the DUT and the monitor
        expect_ok(env_o.agt.drv.state == t, $sformatf("driver state %s, target %s", env_o.agt.drv.state.name(), t.name()));
        expect_ok(env_o.agt.mon.state == t, $sformatf("monitor state %s, target %s", env_o.agt.mon.state.name(), t.name()));
        if (!env_o.cc_o.slave_is_agent())
            expect_ok(env_o.agt.cfg.vif.dbg_state == t, $sformatf("DUT TAP state %0d, target %s (%0d)", env_o.agt.cfg.vif.dbg_state, t.name(), t));
        if (env_o.agt_s != null)
            expect_ok(env_o.agt_s.slv_drv.state == t, $sformatf("slave agent TAP state %s, target %s", env_o.agt_s.slv_drv.state.name(), t.name()));
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_jtag_vec_t tdo;
        super.run_phase(phase);
        phase.raise_objection(this);
        for (int s = 0; s < 16; s++) go_check(odve_jtag_state_e'(s));
        repeat (40) go_check(odve_jtag_state_e'(rng.urand(0, 15)));
        dr('0, 8, tdo);    // at least one scan for the scoreboard
        phase.drop_objection(this);
    endtask : run_phase
endclass : goto_test
