// Passive observer of the TAP pins. It runs its own copy of the TAP
// controller from TMS at every rising TCK (and TRST_n asynchronously), so it
// knows the state without help from either side, and reconstructs:
//   - every reset (entry into Test-Logic-Reset through TMS, or TRST_n low)
//   - every IR/DR scan, Capture to Update, with the bits shifted in (tdi:
//     what Update latches) and out (tdo: what Capture loaded), pauses and
//     the Run-Test/Idle cycles before it.
// A scan cut short by TRST_n is dropped (nothing was updated). Checks
// (uvm_error, counted in n_err):
//   JTAG_X     TMS or TDI unknown at a rising TCK, TDO unknown while shifting
//   JTAG_OE    TDO enabled outside Shift-IR/Shift-DR or disabled inside them (cfg.check_tdo_oe)
//   JTAG_IRCAP the first two bits out of an IR scan are not 1 then 0 (cfg.check_ir_capture)
//   JTAG_LEN   a scan longer than ODVE_JTAG_MAX_LEN
class odve_jtag_mon extends uvm_monitor;
    `uvm_component_utils(odve_jtag_mon)

    uvm_analysis_port #(odve_jtag_item) item_collected_port;
    virtual odve_jtag_if vif;
    odve_jtag_cfg        cfg;

    odve_jtag_state_e state = TLR;
    int unsigned n_seen = 0, n_err = 0, n_err_oe = 0, n_err_ircap = 0;
    int unsigned last_instr = ODVE_JTAG_IDCODE;

    // Functional coverage: covergroups in odve_jtag_agent_pkg; with FCOV=1
    // the build generates their classes and these macros are the whole hook.
    `odve_cov_create(odve_jtag_cg)
    `odve_cov_create(odve_jtag_fsm_cg)

    function new(string name = "odve_jtag_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void publish(odve_jtag_item tr);
        int kind = (tr.kind == JTAG_RESET) ? 0 : (tr.kind == JTAG_IR) ? 1 : 2;
        n_seen++;
        `uvm_info(get_name(), tr.convert2string(), UVM_HIGH)
        `odve_cov_sample(odve_jtag_cg, kind, int'(tr.len), int'(last_instr), int'(tr.n_pause), int'(tr.idle), int'(tr.via_trst))
        item_collected_port.write(tr);
    endfunction

    function void reset_item(bit via_trst, int unsigned idle);
        odve_jtag_item tr = odve_jtag_item::type_id::create("tr");
        tr.kind      = JTAG_RESET;
        tr.via_trst  = via_trst;
        tr.idle      = idle;
        tr.end_state = TLR;
        last_instr   = ODVE_JTAG_IDCODE;
        publish(tr);
    endfunction

    function void err(string id, string msg);
        n_err++;
        if (id == "JTAG_OE")    n_err_oe++;
        if (id == "JTAG_IRCAP") n_err_ircap++;
        `uvm_error(id, $sformatf("%s (TAP state %s)", msg, state.name()))
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_jtag_item    cur;
        odve_jtag_state_e nxt;
        int unsigned      idle_cnt = 0;
        bit               tms, tdi, tdo;
        wait (vif.rst_n === 1'b1);
        forever begin
            @(posedge vif.tck or negedge vif.trst_n);
            if (vif.trst_n === 1'b0) begin
                if (cur != null)
                    `uvm_info(get_name(), $sformatf("TRST_n during a %s scan after %0d bits: scan dropped",
                                                    cur.kind == JTAG_IR ? "IR" : "DR", cur.len), UVM_MEDIUM)
                cur   = null;
                state = TLR;
                reset_item(1, idle_cnt);
                idle_cnt = 0;
                `odve_cov_sample(odve_jtag_fsm_cg, int'(state))
                wait (vif.trst_n !== 1'b0);
                continue;
            end
            if (vif.trst_n !== 1'b1) continue;
            tms = vif.tms;
            tdi = vif.tdi;
            tdo = vif.tdo;
            if ($isunknown(vif.tms)) err("JTAG_X", "TMS unknown at rising TCK");
            if (cfg.check_tdo_oe && vif.tdo_oe !== odve_jtag_is_shift(state))
                err("JTAG_OE", $sformatf("TDO enable is %b", vif.tdo_oe));
            case (state)
                CAP_DR, CAP_IR: begin
                    cur = odve_jtag_item::type_id::create("tr");
                    cur.kind = (state == CAP_IR) ? JTAG_IR : JTAG_DR;
                    cur.len  = 0;
                    cur.idle = idle_cnt;
                end
                SH_DR, SH_IR: if (cur != null) begin
                    if ($isunknown(vif.tdi)) err("JTAG_X", "TDI unknown while shifting");
                    if ($isunknown(vif.tdo)) err("JTAG_X", "TDO unknown while shifting");
                    if (cur.len >= ODVE_JTAG_MAX_LEN) err("JTAG_LEN", $sformatf("scan longer than %0d bits", ODVE_JTAG_MAX_LEN));
                    else begin
                        cur.tdi[cur.len] = tdi;
                        cur.tdo[cur.len] = tdo;
                        cur.len++;
                    end
                end
                RTI: idle_cnt++;
                default: ;
            endcase
            nxt = odve_jtag_next(state, tms);
            if (cur != null && (state == EX1_DR || state == EX1_IR) && (nxt == PA_DR || nxt == PA_IR)) cur.n_pause++;
            if ((state == UPD_DR || state == UPD_IR) && cur != null) begin
                cur.end_state = nxt;
                if (cur.kind == JTAG_IR) begin
                    if (cfg.check_ir_capture && cur.len >= 2 && cur.tdo[1:0] !== 2'b01)
                        err("JTAG_IRCAP", $sformatf("IR scan shifted out %b%b first, expected 1 then 0 (Capture-IR 01)", cur.tdo[0], cur.tdo[1]));
                    // the instruction now in the 4-bit IR of the TAP nearest TDI:
                    // the last 4 bits shifted in, topped up by its Capture-IR bits
                    if (cur.len >= 4) last_instr = (cur.tdi >> (cur.len - 4)) & 4'hF;
                    else              last_instr = ((ODVE_JTAG_IR_CAPTURE >> cur.len) | (cur.tdi << (4 - cur.len))) & 4'hF;
                end
                publish(cur);
                cur = null;
                idle_cnt = 0;
            end
            if (nxt == TLR && state != TLR) begin
                cur = null;
                reset_item(0, idle_cnt);
                idle_cnt = 0;
            end
            state = nxt;
            `odve_cov_sample(odve_jtag_fsm_cg, int'(state))
        end
    endtask
endclass
