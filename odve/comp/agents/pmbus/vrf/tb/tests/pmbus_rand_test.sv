// Random commands back to back over the device's command set on both
// pages, PEC on half of them, a few unsupported codes and invalid values;
// the scoreboard checks every answer, STATUS_CML and SMBALERT#.
// REQ-PMB-001..013.
class pmbus_rand_test extends base_test;
    `uvm_component_utils(pmbus_rand_test)

    function new(string name = "pmbus_rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_pmbus_rand_seq s = odve_pmbus_rand_seq::type_id::create("s");
        super.run_phase(phase);
        phase.raise_objection(this);
        s.rng       = rng.spawn("rand_seq");
        s.n         = 40;
        s.addr      = DEV_ADDR;
        s.p_invalid = 5;
        s.start(env_o.agt.sqr);
        settle();
        if (alert_line()) ara(1);
        send_byte(PMB_CLEAR_FAULTS);
        phase.drop_objection(this);
    endtask : run_phase
endclass : pmbus_rand_test
