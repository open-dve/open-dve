// Builds the env and gives the scenario tests one-line access to the
// controller: every helper builds an item, runs it through
// odve_i3c_xfer_seq on the controller's sequencer and returns the results.
// The scoreboard checks every transfer on its own; the helpers only add
// what a test wants to assert on top.
class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    env       env_o;
    odve_rand rng;
    bit [6:0] pool[$] = '{7'h30, 7'h31, 7'h32, 7'h33};

    function new(string name = "base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_o = env::type_id::create("env_o", this);
        rng   = new(get_full_name());
    endfunction : build_phase

    // With +i3c_target=seq the target agent needs a responder: start the
    // register sequence in the background. It never ends and holds no
    // objection, so the test decides when the run is over.
    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        if (env_o.agt_t != null && env_o.agt_t.slv_sqr != null) begin
            odve_i3c_slv_mem_seq responder = odve_i3c_slv_mem_seq::type_id::create("responder");
            responder.nregs = NREGS;
            fork
                responder.start(env_o.agt_t.slv_sqr);
            join_none
        end
    endtask

    // ---------------------------------------------------------------- helpers
    task xfer(odve_i3c_item it);
        odve_i3c_xfer_seq s = odve_i3c_xfer_seq::type_id::create("xfer");
        s.it = it;
        s.start(env_o.agt.sqr);
    endtask

    function odve_i3c_item mk(odve_i3c_kind_e kind, bit [6:0] addr = 0, bit [7:0] ccc = 0);
        odve_i3c_item it = odve_i3c_item::type_id::create("it");
        it.kind = kind;
        it.addr = addr;
        it.ccc  = ccc;
        it.rnw  = kind inside {I3C_PRIV_RD, I3C_CCC_DR};
        return it;
    endfunction

    task priv_wr(bit [6:0] addr, bit [7:0] bytes[$], int perr_idx = -1, bit use_7e = 1);
        odve_i3c_item it = mk(I3C_PRIV_WR, addr);
        it.data = bytes; it.perr_idx = perr_idx; it.use_7e = use_7e;
        xfer(it);
    endtask

    task priv_rd(bit [6:0] addr, int unsigned len, output odve_i3c_item it, input bit use_7e = 1);
        it = mk(I3C_PRIV_RD, addr);
        it.len = len; it.use_7e = use_7e;
        xfer(it);
    endtask

    task ccc_bc(bit [7:0] ccc, bit [7:0] bytes[$]);
        odve_i3c_item it = mk(I3C_CCC_BC, I3C_BCAST, ccc);
        it.data = bytes;
        xfer(it);
    endtask

    task ccc_dw(bit [7:0] ccc, bit [6:0] addr, bit [7:0] bytes[$], output bit ack);
        odve_i3c_item it = mk(I3C_CCC_DW, addr, ccc);
        it.data = bytes;
        xfer(it);
        ack = it.ack;
    endtask

    task ccc_dr(bit [7:0] ccc, bit [6:0] addr, output odve_i3c_item it);
        it = mk(I3C_CCC_DR, addr, ccc);
        it.len = i3c_get_len(ccc);
        xfer(it);
    endtask

    task entdaa(bit [6:0] p[$], output odve_i3c_item it, input int perr_round = -1);
        it = mk(I3C_ENTDAA, I3C_BCAST, I3C_CCC_ENTDAA);
        it.da_pool = p; it.perr_idx = perr_round;
        xfer(it);
    endtask

    // RSTDAA + ENTDAA: every target on the bus gets an address from `p`
    task assign_all(bit [6:0] p[$]);
        bit [7:0]     none[$];
        odve_i3c_item it;
        ccc_bc(I3C_CCC_RSTDAA, none);
        entdaa(p, it);
        if (it.daa_id.size() != env_o.scb_o.n_online())
            `uvm_error(get_name(), $sformatf("ENTDAA assigned %0d address(es), %0d target(s) on the bus", it.daa_id.size(), env_o.scb_o.n_online()))
    endtask

    // the dynamic addresses of the targets on the bus
    function void das(output bit [6:0] q[$]);
        q.delete();
        foreach (env_o.scb_o.models[i]) if (env_o.scb_o.models[i].online && env_o.scb_o.models[i].has_da) q.push_back(env_o.scb_o.models[i].da);
    endfunction

    // a random private write of n bytes (pointer first) to addr
    task rand_wr(bit [6:0] addr, int unsigned ptr, int unsigned n);
        bit [7:0] b[$];
        b.push_back(8'(ptr));
        repeat (n) b.push_back(8'(rng.u16()));
        priv_wr(addr, b);
    endtask

    task wait_clks(int unsigned n);
        repeat (n) @(posedge env_o.vif.clk);
    endtask
endclass : base_test
