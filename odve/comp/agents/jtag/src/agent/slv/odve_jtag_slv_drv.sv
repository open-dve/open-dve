// Behavioural TAP (the target side). Runs the TAP controller from TMS at
// every rising TCK, captures and shifts there (TDI sampled), updates and
// drives TDO/TDO-enable at the falling edge, and resets asynchronously on
// TRST_n. Drives the interface's s_tdo/s_tdo_oe; top routes them onto the
// bus when the agent plays the target. Two modes (cfg.slv_mode):
//
//   ODVE_JTAG_SLV_MEM  autonomous: the TAP's data registers live in the
//                      driver (odve_jtag_tap_model, from cfg.idcode/pins)
//   ODVE_JTAG_SLV_SEQ  reactive: the IR and the TAP controller stay here,
//                      but every Capture-DR and Update-DR is published on
//                      req_port (the slave sequencer's req_fifo) and the
//                      responding sequence (seq/odve_jtag_slv_reg_seq.sv)
//                      gives the register's length and captured value and
//                      takes the updated value; a TRST_n is passed on
//                      as a JTAG_RESET request
//
// Fault injection for the monitor's checks: cfg.err_ir_capture (Capture-IR
// loads 0000), cfg.err_tdo_oe (TDO enabled in every state).
class odve_jtag_slv_drv extends uvm_driver #(odve_jtag_item);
    `uvm_component_utils(odve_jtag_slv_drv)

    virtual odve_jtag_if vif;
    odve_jtag_cfg        cfg;
    uvm_analysis_port #(odve_jtag_item) req_port;

    odve_jtag_tap_model  tap;            // MEM mode data registers, IR in both modes
    odve_jtag_state_e    state = TLR;
    odve_jtag_vec_t      sr;             // the selected shift register
    int unsigned         sr_len = 1;
    int unsigned         n_capture = 0;

    function new(string name = "odve_jtag_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
        tap = odve_jtag_tap_model::type_id::create("tap");
    endfunction

    virtual function void start_of_simulation_phase(uvm_phase phase);
        tap.idcode         = cfg.idcode;
        tap.pins           = cfg.pins;
        tap.err_ir_capture = cfg.err_ir_capture;
    endfunction

    // A request to the responding sequence and its answer, in zero time.
    // kind JTAG_DR: Capture-DR (is_update 0) or Update-DR (1); JTAG_RESET: TRST_n.
    task ask_seq(odve_jtag_kind_e kind, bit is_update, output odve_jtag_item rsp);
        odve_jtag_item q = odve_jtag_item::type_id::create("q");
        q.kind      = kind;
        q.via_trst  = (kind == JTAG_RESET);
        q.instr     = tap.ir;
        q.is_update = is_update;
        q.tdi       = sr;
        q.len       = sr_len;
        req_port.write(q);
        seq_item_port.get_next_item(rsp);
        seq_item_port.item_done();
    endtask

    task capture_dr();
        odve_jtag_item rsp;
        n_capture++;
        if (cfg.slv_mode == ODVE_JTAG_SLV_MEM) tap.capture_dr(tap.ir, sr_len, sr);
        else begin
            ask_seq(JTAG_DR, 0, rsp);
            sr_len = (rsp.len == 0) ? 1 : rsp.len;
            sr     = rsp.tdi;
        end
    endtask

    task update_dr();
        odve_jtag_item rsp;
        if (cfg.slv_mode == ODVE_JTAG_SLV_MEM) tap.update_dr(tap.ir, sr);
        else ask_seq(JTAG_DR, 1, rsp);
    endtask

    function void shift(bit tdi);
        sr = sr >> 1;
        sr[sr_len - 1] = tdi;
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.s_tdo    <= 1'b0;
        vif.s_tdo_oe <= 1'b0;
        wait (vif.rst_n === 1'b1);
        tap.reset(1);
        forever begin
            @(posedge vif.tck or negedge vif.tck or negedge vif.trst_n);
            if (vif.trst_n === 1'b0) begin
                odve_jtag_item rsp;
                state = TLR;
                tap.reset(1);
                if (cfg.slv_mode == ODVE_JTAG_SLV_SEQ) ask_seq(JTAG_RESET, 0, rsp);
                vif.s_tdo_oe <= cfg.err_tdo_oe;
                wait (vif.trst_n !== 1'b0);
                continue;
            end
            if (vif.tck === 1'b1) begin          // rising: capture / shift, then the next state
                case (state)
                    CAP_IR: begin sr = '0; sr[3:0] = tap.capture_ir(); sr_len = 4; end
                    CAP_DR: capture_dr();
                    SH_IR, SH_DR: shift(vif.tdi);
                    default: ;
                endcase
                state = odve_jtag_next(state, vif.tms);
            end else begin                       // falling: update, TDO
                case (state)
                    TLR:    tap.reset(0);
                    UPD_IR: tap.update_ir(sr);
                    UPD_DR: update_dr();
                    default: ;
                endcase
                vif.s_tdo_oe <= odve_jtag_is_shift(state) || cfg.err_tdo_oe;
                vif.s_tdo    <= odve_jtag_is_shift(state) ? sr[0] : 1'b0;
            end
        end
    endtask
endclass
