// Builds the env and gives the scenario tests the host operations as
// tasks (reset, goto_state, ir, dr, idle), each one sequence on the master
// agent's sequencer. With +jtag_slave=seq the responding register sequence
// is started in the background. Tests compose their traffic from these;
// the scoreboard checks every scan against its model of the chain.
//
// Expected UVM errors: a test that injects faults lists the message IDs it
// expects in expect_ids; a report catcher turns those errors into infos
// and counts them in n_expected, and the test checks the count itself.
class jtag_expect_catcher extends uvm_report_catcher;
    string       ids [$];
    int unsigned n_caught = 0;

    function new(string name = "jtag_expect_catcher");
        super.new(name);
    endfunction

    function action_e catch();
        if (get_severity() == UVM_ERROR) begin
            foreach (ids[i]) if (get_id() == ids[i]) begin
                n_caught++;
                set_severity(UVM_INFO);
                set_message({"(expected) ", get_message()});
                break;
            end
        end
        return THROW;
    endfunction
endclass

class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env                 env_o;
    odve_rand           rng;
    jtag_expect_catcher catcher;
    int unsigned        n_taps = 1;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_o = env::type_id::create("env_o", this);
        rng   = new(get_full_name());
    endfunction : build_phase

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        n_taps = env_o.cc_o.n_taps();
    endfunction

    function void expect_errors(string id);
        if (catcher == null) begin
            catcher = new("catcher");
            uvm_report_cb::add(null, catcher);
        end
        catcher.ids.push_back(id);
    endfunction

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_s != null && env_o.agt_s.slv_sqr != null) begin
            odve_jtag_slv_reg_seq responder = odve_jtag_slv_reg_seq::type_id::create("responder");
            responder.tap.idcode = env_o.cfg_s.idcode;
            responder.tap.pins   = env_o.cfg_s.pins;
            fork
                responder.start(env_o.agt_s.slv_sqr);
            join_none
        end
    endtask

    // ---- host operations ------------------------------------------------
    task reset(bit use_trst = 0, int unsigned idle = 1);
        odve_jtag_reset_seq s = odve_jtag_reset_seq::type_id::create("reset");
        s.use_trst = use_trst;
        s.idle     = idle;
        s.start(env_o.agt.sqr);
    endtask

    task goto_state(odve_jtag_state_e target);
        odve_jtag_goto_seq s = odve_jtag_goto_seq::type_id::create("goto");
        s.target = target;
        s.start(env_o.agt.sqr);
    endtask

    task idle(int unsigned n);
        odve_jtag_idle_seq s = odve_jtag_idle_seq::type_id::create("idle");
        s.len = n;
        s.start(env_o.agt.sqr);
    endtask

    // IR scan; len 0 = 4 bits per TAP of the chain
    task ir(odve_jtag_vec_t v, int unsigned len = 0, int unsigned pause_at = 0,
            int unsigned pause_cycles = 1, int unsigned idle = 0);
        odve_jtag_vec_t unused;
        ir_rd(v, unused, len, pause_at, pause_cycles, idle);
    endtask

    task ir_rd(odve_jtag_vec_t v, output odve_jtag_vec_t tdo, input int unsigned len = 0,
               int unsigned pause_at = 0, int unsigned pause_cycles = 1, int unsigned idle = 0);
        odve_jtag_ir_seq s = odve_jtag_ir_seq::type_id::create("ir");
        s.tdi = v;
        s.len = (len == 0) ? 4 * n_taps : len;
        s.pause_at     = pause_at;
        s.pause_cycles = pause_cycles;
        s.idle         = idle;
        s.start(env_o.agt.sqr);
        tdo = s.tdo;
    endtask

    // the same instruction in every TAP of the chain
    task ir_all(bit [3:0] op, int unsigned idle = 0);
        odve_jtag_vec_t v = '0;
        for (int unsigned t = 0; t < n_taps; t++) v |= odve_jtag_vec_t'(op) << (4 * t);
        ir(v, 0, 0, 1, idle);
    endtask

    task dr(odve_jtag_vec_t v, int unsigned len, output odve_jtag_vec_t tdo,
            input int unsigned pause_at = 0, int unsigned pause_cycles = 1, int unsigned idle = 0);
        odve_jtag_dr_seq s = odve_jtag_dr_seq::type_id::create("dr");
        s.tdi = v;
        s.len = len;
        s.pause_at     = pause_at;
        s.pause_cycles = pause_cycles;
        s.idle         = idle;
        s.start(env_o.agt.sqr);
        tdo = s.tdo;
    endtask

    function void expect_ok(bit ok, string what);
        if (!ok) `uvm_error("TEST", what)
        else     `uvm_info("TEST", {"ok: ", what}, UVM_MEDIUM)
    endfunction

    // the IDCODE of TAP k as a chain-wide 32*n_taps-bit DR read returns it
    function bit [31:0] idcode_in(odve_jtag_vec_t tdo, int unsigned k);
        // the TAP nearest TDO comes out first
        return 32'(tdo >> (32 * (n_taps - 1 - k)));
    endfunction
endclass : base_test
