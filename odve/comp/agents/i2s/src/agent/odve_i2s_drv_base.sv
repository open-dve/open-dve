// Common part of the two I2S drivers (clock controller: mst/, clock
// target: slv/). A transmitter drives SD on the falling SCK edge (UM11732
// section 3.1: the receiver latches on the rising edge); drive_pos() is
// called at each falling edge with the frame position of the SCK period
// that edge starts, and takes the next frame at the first data bit:
//
//   cfg.src == ODVE_I2S_SRC_SEQ  the next item from the sequencer
//                                (try_next_item; none -> an idle frame,
//                                item.gap idle frames before the item)
//   cfg.src == ODVE_I2S_SRC_GEN  autonomous: the driver makes cfg.gen_frames
//                                frames itself (odve_rand stream), then idles
//
// Every frame actually put on the bus (idle ones excepted) is published on
// sent_port, so a scoreboard can check the receiving side against it.
class odve_i2s_drv_base extends uvm_driver #(odve_i2s_item);
    `uvm_component_utils(odve_i2s_drv_base)

    virtual odve_i2s_if vif;
    odve_i2s_cfg        cfg;
    uvm_analysis_port #(odve_i2s_item) sent_port;

    odve_rand           rng;               // SRC_GEN values, item streams
    bit [31:0]          cur [ODVE_I2S_MAX_SLOTS];
    odve_i2s_item       pending;           // fetched, waiting for its gap to pass
    int unsigned        gap_left = 0;
    int unsigned        n_sent = 0, n_idle = 0, n_gen = 0;

    function new(string name = "odve_i2s_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sent_port = new("sent_port", this);
        rng = new(get_full_name());
        foreach (cur[i]) cur[i] = '0;
    endfunction

    // a fresh item of the configured frame shape
    function odve_i2s_item new_item(string name);
        odve_i2s_item it = odve_i2s_item::type_id::create(name);
        it.fmt      = cfg.fmt;
        it.word_len = cfg.word_len;
        it.slot_len = cfg.slot_len;
        it.n_slots  = cfg.n_slots;
        it.mono     = cfg.mono;
        return it;
    endfunction

    // the frame that starts now: cur[] gets its words
    virtual task load_frame();
        odve_i2s_item it;
        if (cfg.src == ODVE_I2S_SRC_GEN) begin
            if (cfg.gen_frames == 0 || n_gen < cfg.gen_frames) begin
                it = new_item($sformatf("gen%0d", n_gen));
                it.rng = rng.spawn(it.get_name());
                it.user_randomize();
                n_gen++;
                use_item(it);
            end else begin
                idle_frame();
            end
            return;
        end
        if (pending == null) begin
            seq_item_port.try_next_item(req);
            if (req != null) begin
                pending  = req;
                gap_left = req.gap;
            end
        end
        if (pending != null && gap_left == 0) begin
            it = pending;
            pending = null;
            use_item(it);
            seq_item_port.item_done();
        end else begin
            if (pending != null) gap_left--;
            idle_frame();
        end
    endtask

    function void use_item(odve_i2s_item it);
        bit [31:0] m = it.mask();
        if (it.n_slots != cfg.n_slots || it.word_len != cfg.word_len)
            `uvm_error(get_name(), $sformatf("item %s does not match the bus format (%s)", it.convert2string(), cfg.convert2string()))
        foreach (cur[i]) cur[i] = (i < cfg.n_slots) ? (it.data[i] & m) : 32'h0;
        n_sent++;
        `uvm_info(get_name(), $sformatf("TX frame %s", it.convert2string()), UVM_HIGH)
        sent_port.write(it);
    endfunction

    function void idle_frame();
        foreach (cur[i]) cur[i] = '0;
        n_idle++;
    endfunction

    // falling edge: SCK period `pos` of the frame begins - put its SD bit out
    virtual task drive_pos(int unsigned pos);
        int unsigned n = cfg.frame_len();
        int unsigned u = (pos + n - cfg.delay()) % n;
        if (u == 0) load_frame();
        vif.a_sd <= cfg.sd_of(u, cur);
    endtask

    virtual function void report_phase(uvm_phase phase);
        if (cfg != null && cfg.dir == ODVE_I2S_TX)
            `uvm_info(get_name(), $sformatf("%0d frames sent, %0d idle frames", n_sent, n_idle), UVM_LOW)
    endfunction
endclass
