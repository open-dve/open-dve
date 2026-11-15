// Passive observer of one I2S bus. Rebuilds every frame from the pins (SD
// and WS sampled on the rising SCK edge, as a receiver latches them,
// UM11732 sections 3.1/3.2), publishes it on item_collected_port and feeds
// the coverage below. Protocol checks, each a uvm_error with its own ID:
//
//   I2S_WS         WS not at the level the frame position requires (glitch,
//                  or a WS edge where none belongs)
//   I2S_FRAME      a frame start after the wrong number of SCK periods, or
//                  no frame start after a whole frame (constant frame length)
//   I2S_X          SD or WS unknown at a sampling edge
//   I2S_PAD        a 1 outside the word bits of a slot (cfg.chk_pad)
//   I2S_MONO       mono frame with left != right (cfg.mono)
//   I2S_TIMING     SCK high or low shorter than 0.35T, or SD/WS changing
//                  less than 0.2T before the rising edge (UM11732 Table 3;
//                  cfg.chk_timing)
//   I2S_CONTENTION two drivers enabled on SCK/WS or on SD at once
//
// After a WS/frame error the monitor drops the frame in progress and
// resynchronises on the next frame start.
class odve_i2s_mon extends uvm_monitor;
    `uvm_component_utils(odve_i2s_mon)

    uvm_analysis_port #(odve_i2s_item) item_collected_port;
    virtual odve_i2s_if vif;
    odve_i2s_cfg        cfg;

    int unsigned n_frames = 0;
    int unsigned n_ws_err = 0, n_frame_err = 0, n_other_err = 0;

    // Functional coverage of what actually went over the bus. The covergroup
    // itself is declared in odve_i2s_agent_pkg (package scope, standard
    // syntax, `ifdef ODVE_COV_NATIVE); with FCOV=1 the build generates
    // odve_cov_pkg::odve_cov_odve_i2s_cg from it and these two macros are the
    // whole hook. Without FCOV=1 both expand to nothing.
    `odve_cov_create(odve_i2s_cg)

    function new(string name = "odve_i2s_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function int role();
        return (cfg.dir == ODVE_I2S_TX ? 0 : 2) + (cfg.clk_role == ODVE_I2S_CLK_MASTER ? 0 : 1);
    endfunction

    function void cov_err(int kind);
        `odve_cov_sample(odve_i2s_cg, int'(cfg.fmt), int'(cfg.word_len), int'(cfg.slot_len), int'(cfg.n_slots), cfg.mono, role(), 7, kind)
    endfunction

    virtual task run_phase(uvm_phase phase);
        fork
            collect();
            check_timing();
            check_contention();
        join
    endtask

    task collect();
        int unsigned n = cfg.frame_len();
        int unsigned pos = 0, u, slot, i;
        bit          synced = 0, win_ok = 0, pad_err = 0;
        logic        ws, sd, prev_ws = 1'bx;
        bit [31:0]   words [ODVE_I2S_MAX_SLOTS];
        forever begin
            @(posedge vif.sck);
            if (vif.rst_n !== 1'b1) begin
                synced = 0; win_ok = 0; prev_ws = 1'bx;
                continue;
            end
            ws = vif.ws;
            sd = vif.sd;
            if ($isunknown(ws) || $isunknown(sd)) begin
                n_other_err++;
                `uvm_error("I2S_X", $sformatf("%s: WS=%b SD=%b at a rising SCK edge", get_full_name(), ws, sd))
                synced = 0; win_ok = 0; prev_ws = 1'bx;
                continue;
            end
            if (prev_ws === !cfg.ws_first() && ws === cfg.ws_first()) begin
                if (synced && pos != n - 1) begin
                    n_frame_err++;
                    cov_err(2);
                    `uvm_error("I2S_FRAME", $sformatf("%s: frame start after %0d SCK periods, expected %0d (misaligned WS)", get_full_name(), pos + 1, n))
                    win_ok = 0;
                end
                pos    = 0;
                synced = 1;
            end else if (synced) begin
                pos++;
                if (pos >= n) begin
                    n_frame_err++;
                    cov_err(2);
                    `uvm_error("I2S_FRAME", $sformatf("%s: no frame start after %0d SCK periods", get_full_name(), n))
                    synced = 0; win_ok = 0;
                end
            end
            prev_ws = ws;
            if (!synced) continue;

            if (ws !== cfg.ws_of(pos)) begin
                n_ws_err++;
                cov_err(1);
                `uvm_error("I2S_WS", $sformatf("%s: WS=%b in SCK period %0d of the frame, expected %b (WS glitch or misaligned)", get_full_name(), ws, pos, cfg.ws_of(pos)))
                synced = 0; win_ok = 0;
                continue;
            end

            u = (pos + n - cfg.delay()) % n;
            if (u == 0) begin
                win_ok  = 1;
                pad_err = 0;
                foreach (words[k]) words[k] = '0;
            end
            if (!win_ok) continue;
            slot = u / cfg.slot_len;
            i    = u % cfg.slot_len;
            if (i >= cfg.offset() && i < cfg.offset() + cfg.word_len) words[slot] = {words[slot][30:0], sd};
            else if (sd) pad_err = 1;
            if (u == n - 1) publish(words, pad_err);
        end
    endtask

    function void publish(bit [31:0] words [ODVE_I2S_MAX_SLOTS], bit pad_err);
        odve_i2s_item tr = odve_i2s_item::type_id::create("tr");
        tr.fmt      = cfg.fmt;
        tr.word_len = cfg.word_len;
        tr.slot_len = cfg.slot_len;
        tr.n_slots  = cfg.n_slots;
        tr.mono     = cfg.mono;
        foreach (words[k]) tr.data[k] = (k < cfg.n_slots) ? (words[k] & tr.mask()) : 32'h0;
        n_frames++;
        if (pad_err && cfg.chk_pad) begin
            n_other_err++;
            `uvm_error("I2S_PAD", $sformatf("%s: SD high outside the %0d word bits of a slot in frame %s", get_full_name(), cfg.word_len, tr.convert2string()))
        end
        if (cfg.mono && tr.data[0] != tr.data[1]) begin
            n_other_err++;
            `uvm_error("I2S_MONO", $sformatf("%s: mono frame with left != right: %s", get_full_name(), tr.convert2string()))
        end
        `uvm_info(get_name(), $sformatf("frame %s", tr.convert2string()), UVM_HIGH)
        `odve_cov_sample(odve_i2s_cg, int'(cfg.fmt), int'(cfg.word_len), int'(cfg.slot_len), int'(cfg.n_slots), cfg.mono, role(), int'(tr.val_class(0)), 0)
        item_collected_port.write(tr);
    endfunction

    // SCK duty cycle and SD/WS set-up time against the rising edge
    task check_timing();
        realtime t_rise = 0, t_fall = 0, t_chg = 0, now, per, hi, lo;
        int unsigned n_rise = 0;
        if (!cfg.chk_timing) return;
        fork
            forever begin
                @(vif.sd or vif.ws);
                t_chg = $realtime;
            end
            forever begin
                @(negedge vif.sck);
                t_fall = $realtime;
            end
            forever begin
                @(posedge vif.sck);
                now = $realtime;
                if (vif.rst_n !== 1'b1) begin
                    n_rise = 0;
                end else begin
                    n_rise++;
                    if (n_rise > 2) begin
                        per = now - t_rise;
                        hi  = t_fall - t_rise;
                        lo  = now - t_fall;
                        if (hi < 0.35 * per || lo < 0.35 * per) begin
                            n_other_err++;
                            `uvm_error("I2S_TIMING", $sformatf("%s: SCK high %0.1f / low %0.1f in a period of %0.1f (>= 0.35T each)", get_full_name(), hi, lo, per))
                        end
                        if (t_chg < now && t_chg > t_rise && now - t_chg < 0.2 * per) begin
                            n_other_err++;
                            `uvm_error("I2S_TIMING", $sformatf("%s: SD/WS changed %0.1f before the rising SCK edge, set-up >= 0.2T = %0.1f", get_full_name(), now - t_chg, 0.2 * per))
                        end
                    end
                end
                t_rise = now;
            end
        join
    endtask

    task check_contention();
        forever begin
            @(vif.a_clk_oe or vif.d_clk_oe or vif.a_sd_oe or vif.d_sd_oe);
            if (vif.a_clk_oe === 1'b1 && vif.d_clk_oe === 1'b1) begin
                n_other_err++;
                `uvm_error("I2S_CONTENTION", $sformatf("%s: SCK/WS driven by the agent and the other side at once", get_full_name()))
            end
            if (vif.a_sd_oe === 1'b1 && vif.d_sd_oe === 1'b1) begin
                n_other_err++;
                `uvm_error("I2S_CONTENTION", $sformatf("%s: SD driven by the agent and the other side at once", get_full_name()))
            end
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d frames observed, %0d WS errors, %0d frame-length errors, %0d other errors", n_frames, n_ws_err, n_frame_err, n_other_err), UVM_LOW)
    endfunction
endclass
