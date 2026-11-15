// Clock controller ("master"): generates SCK (period 2*cfg.sck_half_ns, 50 %
// duty) and WS continuously from the moment reset is released, and - as a
// transmitter - SD. WS and SD change on the falling edge. A receiver
// controller only makes the clocks; its monitor reads the data.
//
// Error injection (cfg.inj_kind, in frame cfg.inj_frame, once):
//   ODVE_I2S_INJ_WS_GLITCH  WS inverted for one SCK period in the middle of
//                           the first slot (a glitch on word select)
//   ODVE_I2S_INJ_WS_SHIFT   the next frame starts one SCK early (a frame one
//                           period short: misaligned word select)
class odve_i2s_mst_drv extends odve_i2s_drv_base;
    `uvm_component_utils(odve_i2s_mst_drv)

    int unsigned n_frames = 0;
    bit          inj_done = 0;

    function new(string name = "odve_i2s_mst_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        int unsigned n = cfg.frame_len();
        int unsigned pos = n - 2;          // start with the last period of a frame, so that
                                           // every target sees one rising edge before the first frame start
        int unsigned q;
        bit          w;
        vif.a_sck    <= 1'b1;
        vif.a_ws     <= cfg.ws_of(n - 1);
        vif.a_clk_oe <= 1'b1;
        if (cfg.dir == ODVE_I2S_TX) begin
            vif.a_sd    <= 1'b0;
            vif.a_sd_oe <= 1'b1;
        end
        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);
        #1;                                // keep SCK edges off the reference clock edges
        forever begin
            q = (pos + 1) % n;
            if (!inj_done && cfg.inj_kind == ODVE_I2S_INJ_WS_SHIFT && n_frames == cfg.inj_frame + 1 && pos == n - 2) begin
                `uvm_info(get_name(), $sformatf("injecting WS shift: frame %0d ends after %0d SCK periods", cfg.inj_frame, n - 1), UVM_LOW)
                q = 0;
                inj_done = 1;
            end
            if (q == 0) n_frames++;
            w = cfg.ws_of(q);
            if (!inj_done && cfg.inj_kind == ODVE_I2S_INJ_WS_GLITCH && n_frames == cfg.inj_frame + 1 && q == cfg.slot_len / 2) begin
                `uvm_info(get_name(), $sformatf("injecting WS glitch in frame %0d, SCK period %0d", cfg.inj_frame, q), UVM_LOW)
                w = !w;
                inj_done = 1;
            end
            vif.a_sck <= 1'b0;
            vif.a_ws  <= w;
            pos = q;
            if (cfg.dir == ODVE_I2S_TX) drive_pos(pos);
            #(cfg.sck_half_ns);
            vif.a_sck <= 1'b1;
            #(cfg.sck_half_ns);
        end
    endtask
endclass
