// Clock target ("slave"): SCK and WS come from the other side. The frame
// position is derived from WS, latched on the rising edge as the target
// does (UM11732 section 3.2); a frame starts at the WS edge into the first
// slot's level. Once synchronised, a transmitter target drives SD on each
// falling edge for the SCK period that edge starts - for LJ/RJ the first
// data bit shares its period with the WS edge, so the driver relies on the
// constant frame length and sends idle frames until it has seen one start.
// A receiver target has nothing to drive (the monitor reads the data).
class odve_i2s_slv_drv extends odve_i2s_drv_base;
    `uvm_component_utils(odve_i2s_slv_drv)

    function new(string name = "odve_i2s_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        int unsigned n = cfg.frame_len();
        int unsigned pos = 0;
        bit          synced = 0;
        logic        ws, prev_ws = 1'bx;
        if (cfg.dir != ODVE_I2S_TX) return;
        vif.a_sd    <= 1'b0;
        vif.a_sd_oe <= 1'b1;
        forever begin
            @(posedge vif.sck);
            if (vif.rst_n !== 1'b1) begin
                synced  = 0;
                prev_ws = 1'bx;
                continue;
            end
            ws = vif.ws;
            if (prev_ws === !cfg.ws_first() && ws === cfg.ws_first()) begin
                pos    = 0;
                synced = 1;
            end else begin
                pos = (pos + 1) % n;
            end
            prev_ws = ws;
            @(negedge vif.sck);
            if (synced) drive_pos((pos + 1) % n);
            else        vif.a_sd <= 1'b0;
        end
    endtask
endclass
