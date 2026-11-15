// Negative test: the port A controller (transmitter agent) puts a WS error
// in frame 4 - a one-SCK glitch on WS (default, +i2s_inj=glitch) or a frame
// one SCK short (+i2s_inj=shift). The port A monitor must report it
// (I2S_WS / I2S_FRAME); those errors are expected here, so a report catcher
// turns them into infos and counts them, and the test fails if there were
// none or if the monitor did not resynchronise and keep rebuilding frames.
// The scoreboard only counts (the corrupted frame cannot be predicted) and
// resynchronises; all but the frames around the error must still arrive
// intact on both ports.
class i2s_err_catcher extends uvm_report_catcher;
    int unsigned n = 0;
    string       ids[$];     // the expected error IDs
    function new(string name = "i2s_err_catcher");
        super.new(name);
    endfunction
    function bit expected(string id);
        foreach (ids[i]) if (ids[i] == id) return 1;
        return 0;
    endfunction
    function action_e catch();
        if (get_severity() == UVM_ERROR && expected(get_id())) begin
            n++;
            set_severity(UVM_INFO);
            set_message({"expected: ", get_message()});
        end
        return THROW;
    endfunction
endclass

class i2s_ws_err_test extends base_test;
    `uvm_component_utils(i2s_ws_err_test)

    i2s_err_catcher catcher;

    function new(string name = "i2s_ws_err_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void configure();
        tc.inj       = ODVE_I2S_INJ_WS_GLITCH;
        tc.frames    = 16;
        tc.scb_check = 0;
    endfunction

    // no all-zero frames: they would not count as received (idle frames)
    virtual function odve_i2s_base_seq make_seq();
        odve_i2s_base_seq seq = odve_i2s_frame_seq::type_id::create("frames");
        seq.w_val = '{70, 0, 10, 10, 10};
        return seq;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        catcher = new("catcher");
        catcher.ids = '{"I2S_WS", "I2S_FRAME"};
        uvm_report_cb::add(null, catcher);
    endfunction

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (catcher.n == 0)
            `uvm_error(get_name(), $sformatf("injected %s not reported by the monitor", tc.inj.name()))
        else
            `uvm_info(get_name(), $sformatf("injected %s reported %0d time(s) by the monitor", tc.inj.name(), catcher.n), UVM_LOW)
        // after the error everything must get through again: at most the
        // frame hit by the error (and one on each side of it) may be lost
        if (env_o.scb_o.match_a + 3 < tc.frames)
            `uvm_error(get_name(), $sformatf("port A: %0d of %0d frames received intact after resynchronisation", env_o.scb_o.match_a, tc.frames))
        if (tc.has_dut() && env_o.scb_o.match_b + 3 < tc.frames)
            `uvm_error(get_name(), $sformatf("port B: %0d of %0d frames through the DUT intact after resynchronisation", env_o.scb_o.match_b, tc.frames))
        if (env_o.mon_a.n_frames < tc.frames)
            `uvm_error(get_name(), $sformatf("monitor rebuilt %0d frames, expected >= %0d (no resynchronisation after the error?)", env_o.mon_a.n_frames, tc.frames))
    endfunction
endclass
