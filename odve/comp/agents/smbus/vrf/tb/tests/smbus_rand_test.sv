// Random messages back to back over the device's whole command set, PEC on
// half of them, block lengths 0..32; SET_ALERT / CLEAR_STATUS appear
// randomly, so SMBALERT# toggles and is checked after every message; an ARA
// read releases it at the end. REQ-SMB-001..012, 017.
class smbus_rand_test extends base_test;
    `uvm_component_utils(smbus_rand_test)

    function new(string name = "smbus_rand_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_smbus_rand_seq s = odve_smbus_rand_seq::type_id::create("s");
        super.run_phase(phase);
        phase.raise_objection(this);
        s.rng      = rng.spawn("rand_seq");
        s.n        = 50;
        s.tgt_addr = DEV_ADDR;
        s.set_from_tab(env_o.cfg.cmd_tab);
        s.start(env_o.agt.sqr);
        settle();
        if (alert_line()) send(mk(SMB_ARA, 8'h00, rng.chance(50), SMB_ARA_ADDR));
        msg(SMB_SEND_BYTE, 8'h40);
        phase.drop_objection(this);
    endtask : run_phase
endclass : smbus_rand_test
