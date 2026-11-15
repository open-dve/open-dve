// Hot-Join (+i3c_target=both): the target agent starts offline, ENTDAA
// assigns the RTL target only. The agent then comes online and requests a
// Hot-Join (7'h02/W after a START request): first the controller NACKs it
// (the agent drops the request), then ACKs a second one, after which an
// ENTDAA gives the agent its address and private transfers reach it.
class hotjoin_test extends base_test;
    `uvm_component_utils(hotjoin_test)

    function new(string name = "hotjoin_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (env_o.cfg_t == null) `uvm_fatal(get_name(), "hotjoin_test needs the target agent: +i3c_target=both|mem")
        env_o.cfg_t.offline = 1;
        env_o.scb_o.m_tgt.online = 0;
    endfunction

    task wait_hj(bit acked, string what);
        fork
            if (acked) wait (env_o.agt.drv.n_hj_ack >= 1);
            else       wait (env_o.agt.drv.n_hj_nack >= 1);
            begin wait_clks(20000); `uvm_error(get_name(), $sformatf("%s: no Hot-Join seen", what)) end
        join_any
        disable fork;
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_i3c_item it;
        bit [6:0]     q[$];
        super.run_phase(phase);
        phase.raise_objection(this);
        assign_all(pool);
        env_o.cfg_t.offline = 0;
        env_o.scb_o.m_tgt.online = 1;

        env_o.cfg.hj_ack = 0;
        env_o.agt_t.slv_drv.request_hj();
        wait_hj(0, "NACKed Hot-Join");
        wait_clks(500);
        if (env_o.agt.drv.n_hj_nack != 1) `uvm_error(get_name(), "Hot-Join retried after a NACK")

        env_o.cfg.hj_ack = 1;
        env_o.agt_t.slv_drv.request_hj();
        wait_hj(1, "ACKed Hot-Join");

        entdaa(pool, it);
        if (it.daa_id.size() != 1) `uvm_error(get_name(), $sformatf("ENTDAA after Hot-Join: %0d round(s), 1 expected", it.daa_id.size()))
        das(q);
        foreach (q[i]) begin
            rand_wr(q[i], 0, 4);
            priv_wr(q[i], '{8'h00});
            priv_rd(q[i], 4, it);
        end
        phase.drop_objection(this);
    endtask : run_phase
endclass : hotjoin_test
