// JTAG host. Owns TCK: one TCK period is 2 * cfg.tck_half cycles of the
// testbench clk. Every TCK cycle is a falling edge, where TMS/TDI change,
// then a rising edge, where the target samples them and where the host
// samples TDO (which the target changed at the falling edge). The driver
// keeps its own copy of the TAP state and reaches any state along the
// shortest TMS path (goto), so a scan can start from wherever the TAP is.
class odve_jtag_mst_drv_base extends uvm_driver #(odve_jtag_item);
    `uvm_component_utils(odve_jtag_mst_drv_base)

    virtual odve_jtag_if vif;
    odve_jtag_cfg        cfg;
    odve_jtag_state_e    state = TLR;
    int unsigned         n_tck = 0;

    function new(string name = "odve_jtag_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // One TCK cycle with the given TMS/TDI; returns TDO as sampled at the rising edge.
    task cycle(bit tms, bit tdi, output bit tdo);
        repeat (cfg.tck_half) @(posedge vif.clk);
        vif.tck <= 1'b0;
        vif.tms <= tms;
        vif.tdi <= tdi;
        repeat (cfg.tck_half) @(posedge vif.clk);
        tdo = vif.tdo;
        vif.tck <= 1'b1;
        state = odve_jtag_next(state, tms);
        n_tck++;
    endtask

    task cyc(bit tms);
        bit unused;
        cycle(tms, 1'b0, unused);
    endtask

    // Shortest TMS sequence from `from` to `to` (breadth-first over the 16 states).
    function void tms_path(odve_jtag_state_e from, odve_jtag_state_e to, ref bit path[$]);
        int  prev [16];
        bit  ptms [16];
        bit  seen [16];
        int  q [$];
        int  s, n;
        path.delete();
        if (from == to) return;
        foreach (seen[i]) seen[i] = 0;
        seen[from] = 1;
        q.push_back(from);
        while (q.size() > 0) begin
            s = q.pop_front();
            for (int t = 0; t < 2; t++) begin
                n = odve_jtag_next(odve_jtag_state_e'(s), t[0]);
                if (!seen[n]) begin
                    seen[n] = 1;
                    prev[n] = s;
                    ptms[n] = t[0];
                    q.push_back(n);
                end
            end
        end
        n = to;
        while (n != from) begin
            path.push_front(ptms[n]);
            n = prev[n];
        end
    endfunction

    task goto(odve_jtag_state_e to);
        bit path[$];
        tms_path(state, to, path);
        foreach (path[i]) cyc(path[i]);
    endtask

    task do_idle(int unsigned n);
        if (n == 0) return;
        goto(RTI);
        repeat (n) cyc(1'b0);
    endtask

    task do_reset(odve_jtag_item req);
        if (req.use_trst) begin
            // asserted between edges, held two TCK periods with TMS high
            repeat (cfg.tck_half) @(posedge vif.clk);
            vif.trst_n <= 1'b0;
            vif.tms    <= 1'b1;
            repeat (2) cyc(1'b1);
            vif.trst_n <= 1'b1;
            state = TLR;
        end else begin
            repeat (req.len < 5 ? 5 : req.len) cyc(1'b1);
            if (state != TLR) `uvm_error(get_name(), $sformatf("host TAP copy in %s after TMS reset", state.name()))
        end
        do_idle(req.idle);
    endtask

    // Capture -> Shift (len bits, optional pause) -> Update -> Run-Test/Idle.
    task do_scan(odve_jtag_item req);
        bit ir = (req.kind == JTAG_IR);
        bit tdo, last, pz;
        goto(ir ? CAP_IR : CAP_DR);
        req.tdo = '0;
        if (req.len == 0) cyc(1'b1);                     // Capture -> Exit1, nothing shifted
        else begin
            cyc(1'b0);                                   // Capture -> Shift (the capture happens here)
            for (int unsigned i = 0; i < req.len; i++) begin
                last = (i == req.len - 1);
                pz   = (req.pause_at != 0 && i == req.pause_at - 1);
                cycle(last || pz, req.tdi[i], tdo);
                req.tdo[i] = tdo;
                if (pz) begin                            // Exit1 -> Pause, wait, -> Exit2
                    cyc(1'b0);
                    repeat (req.pause_cycles) cyc(1'b0);
                    cyc(1'b1);
                    if (!last) cyc(1'b0);                // Exit2 -> Shift: resume
                end
            end
        end
        cyc(1'b1);                                       // Exit1/Exit2 -> Update
        cyc(1'b0);                                       // Update -> Run-Test/Idle
        repeat (req.idle) cyc(1'b0);
    endtask

    virtual task run_phase(uvm_phase phase);
        vif.tck    <= 1'b0;
        vif.tms    <= 1'b1;
        vif.tdi    <= 1'b0;
        vif.trst_n <= 1'b1;
        wait (vif.rst_n === 1'b1);
        state = TLR;           // power-on reset puts every TAP in Test-Logic-Reset
        @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info(get_name(), $sformatf("drive %s", req.convert2string()), UVM_HIGH)
            case (req.kind)
                JTAG_RESET:     do_reset(req);
                JTAG_IR, JTAG_DR: do_scan(req);
                JTAG_IDLE:      do_idle(req.len);
                JTAG_GOTO:      goto(req.target);
                default: ;
            endcase
            req.end_state = state;
            seq_item_port.item_done();
        end
    endtask
endclass
