// In-Band Interrupts (run with +i3c_target=both; works with one target too).
//  1. each target alone on an idle bus: START request, arbitration header,
//     controller ACK, Mandatory Data Byte from the RTL target (BCR[2]),
//     none from the agent (BCR[2] = 0) - the scoreboard checks the MDB
//  2. both at once: the lower dynamic address must win, the other follows
//  3. an IBI raised while the controller is busy: it wins the header after
//     one of the controller's STARTs, the controller's transfer is retried
//  4. controller NACKs (cfg.ibi_ack = 0): the RTL target keeps retrying in
//     every header after START; the controller sends DISEC after the Sr
//     that follows its NACK; GETSTATUS then shows the IBI pending; no IBI
//     while disabled (scoreboard); ENEC with ibi_ack = 1 delivers it
class ibi_test extends base_test;
    `uvm_component_utils(ibi_test)

    function new(string name = "ibi_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    task dut_ibi(bit [7:0] mdb);
        env_o.vif.d_ibi_mdb <= mdb;
        env_o.vif.d_ibi_req <= 1'b1;
        @(posedge env_o.vif.clk);
        env_o.vif.d_ibi_req <= 1'b0;
        env_o.scb_o.m_dut.exp_mdb.push_back(mdb);
    endtask

    task wait_ibis(int unsigned n, string what);
        fork
            wait (env_o.scb_o.ibi_order.size() >= n);
            begin wait_clks(20000); `uvm_error(get_name(), $sformatf("%s: %0d IBI(s) expected, %0d seen", what, n, env_o.scb_o.ibi_order.size())) end
        join_any
        disable fork;
    endtask

    virtual task run_phase(uvm_phase phase);
        odve_i3c_item  it;
        i3c_tgt_model  d = env_o.scb_o.m_dut, t = env_o.scb_o.m_tgt;
        bit [6:0]      q[$];
        bit            ack;
        int unsigned   n;
        super.run_phase(phase);
        phase.raise_objection(this);
        assign_all(pool);
        das(q);

        // 1. one at a time
        if (d != null) begin dut_ibi(8'hA5); wait_ibis(1, "RTL target IBI"); end
        if (t != null) begin env_o.agt_t.slv_drv.request_ibi(8'h00); wait_ibis(env_o.scb_o.ibi_order.size() + 1, "target agent IBI"); end

        // 2. both at once: lower dynamic address first
        if (d != null && t != null) begin
            n = env_o.scb_o.ibi_order.size();
            dut_ibi(8'h5C);
            env_o.agt_t.slv_drv.request_ibi(8'h00);
            wait_ibis(n + 2, "simultaneous IBIs");
            if (env_o.scb_o.ibi_order[n] != ((d.da < t.da) ? d.da : t.da))
                `uvm_error(get_name(), $sformatf("simultaneous IBIs: 0x%02h won, the lower address is 0x%02h", env_o.scb_o.ibi_order[n], (d.da < t.da) ? d.da : t.da))
        end

        // 3. raised while the controller keeps the bus busy
        // (back-to-back transfers leave the bus idle for t_buf < t_aval clks, so
        // the IBI can only get in by arbitrating after one of their STARTs)
        n = env_o.scb_o.ibi_order.size();
        fork
            begin
                wait_clks(150);
                if (d != null) dut_ibi(8'h3C);
                else           env_o.agt_t.slv_drv.request_ibi(8'h00);
            end
        join_none
        repeat (3) foreach (q[i]) begin
            rand_wr(q[i], 1, 2);
            priv_rd(q[i], 2, it);
        end
        wait_ibis(n + 1, "IBI during traffic");

        // 4. NACK, DISEC, pending, ENEC
        if (d != null) begin
            env_o.cfg.ibi_ack = 0;
            dut_ibi(8'h77);
            fork
                wait (d.n_ibi_nack > 0);
                begin wait_clks(20000); `uvm_error(get_name(), "no NACKed IBI seen") end
            join_any
            disable fork;
            ccc_dw(I3C_CCC_DISEC_D, d.da, '{I3C_EVT_ENINT}, ack);   // goes out after Sr, behind a NACKed IBI
            n = d.n_ibi_nack;
            wait_clks(2000);
            if (d.n_ibi_nack != n) `uvm_error(get_name(), "IBI requests continued after DISEC")
            ccc_dr(I3C_CCC_GETSTATUS, d.da, it);
            if (it.data.size() != 2 || !it.data[1][0]) `uvm_error(get_name(), "GETSTATUS[0]: no IBI pending after DISEC")
            n = env_o.scb_o.ibi_order.size();
            env_o.cfg.ibi_ack = 1;
            ccc_dw(I3C_CCC_ENEC_D, d.da, '{I3C_EVT_ENINT}, ack);
            wait_ibis(n + 1, "IBI after ENEC");
            ccc_dr(I3C_CCC_GETSTATUS, d.da, it);
            if (it.data.size() != 2 || it.data[1][0]) `uvm_error(get_name(), "GETSTATUS[0]: IBI still pending after delivery")
        end
        `uvm_info(get_name(), $sformatf("IBIs ACKed: %0d, NACKed: %0d", env_o.agt.drv.n_ibi_ack, env_o.agt.drv.n_ibi_nack), UVM_LOW)
        phase.drop_objection(this);
    endtask : run_phase
endclass : ibi_test
