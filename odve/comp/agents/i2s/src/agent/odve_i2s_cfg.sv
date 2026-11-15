// Configuration of one I2S agent instance. Direction (transmitter /
// receiver) and clock role (controller = generates SCK and WS / target =
// follows them) are independent, as in the I2S specification (UM11732
// section 2): a transmitter or a receiver may be the controller.
class odve_i2s_cfg extends uvm_object;
    `uvm_object_utils(odve_i2s_cfg)

    odve_i2s_dir_e      dir      = ODVE_I2S_TX;
    odve_i2s_clk_role_e clk_role = ODVE_I2S_CLK_MASTER;
    odve_i2s_src_e      src      = ODVE_I2S_SRC_SEQ;   // transmitter: frames from the sequencer or generated
    bit                 has_mon  = 1;                   // one monitor per bus
    virtual odve_i2s_if vif;

    // frame format, the same on every device of the bus
    odve_i2s_fmt_e fmt      = ODVE_I2S_FMT_I2S;
    int unsigned   word_len = 16;    // 16, 24, 32 (<= slot_len)
    int unsigned   slot_len = 32;    // 16 or 32 SCK periods per slot
    int unsigned   n_slots  = 2;     // 2 for I2S/LJ/RJ; 2..8 for TDM
    bit            mono     = 0;     // stereo formats: left == right (monitor checks)

    // controller: SCK half period (T = 2 * sck_half_ns)
    int unsigned   sck_half_ns = 80;

    // monitor checks
    bit            chk_pad    = 1;   // bits outside the word must be 0
    bit            chk_timing = 1;   // tHC/tLC >= 0.35T, set-up >= 0.2T (UM11732 Table 3)

    // SRC_GEN: number of frames the driver generates on its own (then idle)
    int unsigned   gen_frames = 16;

    // controller error injection (negative tests)
    odve_i2s_inj_e inj_kind  = ODVE_I2S_INJ_NONE;
    int unsigned   inj_frame = 4;    // frame index (0 = first frame) the error is put in

    function new(string name = "odve_i2s_cfg");
        super.new(name);
    endfunction

    // SCK periods per frame
    function int unsigned frame_len();
        return n_slots * slot_len;
    endfunction

    // WS level of the first slot (left channel / TDM frame pulse)
    function bit ws_first();
        return (fmt == ODVE_I2S_FMT_I2S) ? 1'b0 : 1'b1;
    endfunction

    // SCK periods between the frame start (WS edge) and the first data bit
    function int unsigned delay();
        return (fmt == ODVE_I2S_FMT_I2S || fmt == ODVE_I2S_FMT_TDM) ? 1 : 0;
    endfunction

    // first bit of the word inside its slot (right-justified: word ends with the slot)
    function int unsigned offset();
        return (fmt == ODVE_I2S_FMT_RJ) ? slot_len - word_len : 0;
    endfunction

    // WS level in SCK period `pos` of a frame (pos 0 = the WS edge)
    function bit ws_of(int unsigned pos);
        if (fmt == ODVE_I2S_FMT_TDM) return pos == 0;
        return (pos < slot_len) ? ws_first() : !ws_first();
    endfunction

    // SD bit for window position u (u = SCK periods since the first data
    // bit of the frame) of a frame whose words are `w`
    function bit sd_of(int unsigned u, input bit [31:0] w [ODVE_I2S_MAX_SLOTS]);
        int unsigned slot = u / slot_len;
        int unsigned i    = u % slot_len;
        if (i < offset() || i >= offset() + word_len) return 1'b0;
        return w[slot][word_len - 1 - (i - offset())];
    endfunction

    function string check();
        if (!(word_len inside {16, 24, 32}))   return $sformatf("word_len %0d: 16, 24 or 32", word_len);
        if (!(slot_len inside {16, 32}))       return $sformatf("slot_len %0d: 16 or 32", slot_len);
        if (word_len > slot_len)               return $sformatf("word_len %0d > slot_len %0d", word_len, slot_len);
        if (fmt != ODVE_I2S_FMT_TDM && n_slots != 2) return "I2S/LJ/RJ frames have 2 slots";
        if (n_slots < 2 || n_slots > ODVE_I2S_MAX_SLOTS) return $sformatf("n_slots %0d: 2..%0d", n_slots, ODVE_I2S_MAX_SLOTS);
        if (mono && fmt == ODVE_I2S_FMT_TDM)   return "mono is a stereo-format mode";
        return "";
    endfunction

    function string convert2string();
        return $sformatf("%s %s %s w%0d s%0d x%0d%s", dir.name(), clk_role.name(), fmt.name(), word_len, slot_len, n_slots, mono ? " mono" : "");
    endfunction
endclass
