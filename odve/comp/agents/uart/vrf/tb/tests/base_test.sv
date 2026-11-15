// Builds the env; starts the slave agent's responder in +uart_slave=seq
// mode; helpers for the scenario tests: set_format(), send() (random
// characters through odve_uart_base_seq), send_pattern(), wait_drain().
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env       env_o;
    odve_rand rng;

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_o = env::type_id::create("env_o", this);
        rng   = new(get_full_name());
    endfunction : build_phase

    // With +uart_slave=seq the slave agent needs a responder: start the echo
    // sequence in the background before any test traffic. It never ends and
    // holds no objection, so the test decides when the run is over.
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_s != null && env_o.agt_s.slv_sqr != null) begin
            odve_uart_slv_echo_seq responder = odve_uart_slv_echo_seq::type_id::create("responder");
            fork
                responder.start(env_o.agt_s.slv_sqr);
            join_none
        end
    endtask

    function void set_format(int unsigned bits, odve_uart_parity_e par, odve_uart_stop_e stop, bit flow = 0);
        env_o.set_format(bits, par, stop, flow);
    endfunction

    // n random characters in the current format
    task send(int unsigned n, int unsigned gap_pct = 30, int unsigned err_pct = 0);
        odve_uart_base_seq seq = odve_uart_base_seq::type_id::create("seq");
        seq.rng     = rng.spawn("seq");
        seq.n       = n;
        seq.gap_pct = gap_pct;
        seq.err_pct = err_pct;
        seq.start(env_o.agt.sqr);
    endtask

    // n error events of one kind (0 bad parity, 1 bad stop, 2 break, 3 glitch)
    task send_err(int unsigned n, int unsigned kind);
        odve_uart_base_seq seq = odve_uart_base_seq::type_id::create("seq_err");
        seq.rng     = rng.spawn("seq_err");
        seq.n       = n;
        seq.err_pct = 100;
        seq.err_w   = '{0, 0, 0, 0};
        seq.err_w[kind] = 1;
        seq.start(env_o.agt.sqr);
    endtask

    task send_pattern(int unsigned idle_bits = 0);
        odve_uart_pattern_seq seq = odve_uart_pattern_seq::type_id::create("pat");
        seq.idle_bits = idle_bits;
        seq.start(env_o.agt.sqr);
    endtask

    // Wait until every expected echo has come back and both lines have been
    // at mark for more than a frame time; error after max_bits bit times.
    task wait_drain(int unsigned max_bits = 4000);
        virtual odve_uart_if vif = env_o.cfg.vif;
        int unsigned quiet = 0, waited = 0;
        while (quiet < 16) begin
            repeat (env_o.cfg.bit_clks) @(posedge vif.clk);
            waited++;
            if (env_o.scb_o.pending() != 0 || vif.txd !== 1'b1 || vif.rxd !== 1'b1) quiet = 0;
            else                                                                    quiet++;
            if (waited > max_bits) begin
                `uvm_error(get_name(), $sformatf("link not drained after %0d bit times: %0d echo(es) outstanding", max_bits, env_o.scb_o.pending()))
                return;
            end
        end
    endtask
endclass : base_test
