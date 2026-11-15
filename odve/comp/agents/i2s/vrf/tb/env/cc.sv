// Configuration of the testbench, made by the test (base_test::configure,
// then plusargs, which win) and read by the env:
//
// who is on the buses
//   +i2s_slave=dut     port A: agent transmitter -> DUT receiver; port B:
//                      DUT transmitter -> agent receiver (default)
//   +i2s_slave=agent   port A: agent transmitter -> agent receiver, no DUT
//                      traffic (both agent directions checked against each other)
//   +i2s_a_clk=tx|rx   clock controller of port A: the transmitter agent
//                      (default) or the receiver (DUT, or the receiver agent)
//   +i2s_b_clk=tx|rx   clock controller of port B: the DUT (default) or the
//                      receiver agent
// frame format (default: what the test chose)
//   +i2s_fmt=i2s|lj|rj|tdm  +i2s_wlen=16|24|32  +i2s_slen=16|32  +i2s_slots=N
//   +i2s_mono  +i2s_frames=N
//   +i2s_sck_half=NS  SCK half period of every controller (multiple of 10, >= 40)
// negative tests
//   +i2s_inj=glitch|shift   error injected by the port A controller agent
class cc extends uvm_object;
    `uvm_object_utils(cc)

    string         slave  = "dut";
    string         a_clk  = "tx";
    string         b_clk  = "tx";
    odve_i2s_fmt_e fmt    = ODVE_I2S_FMT_I2S;
    int unsigned   wlen   = 16;
    int unsigned   slen   = 32;
    int unsigned   nslots = 2;
    bit            mono   = 0;
    int unsigned   frames = 24;          // frames the test sends
    odve_i2s_src_e src    = ODVE_I2S_SRC_SEQ;
    odve_i2s_inj_e inj    = ODVE_I2S_INJ_NONE;
    int unsigned   sck_half_ns = 80;     // T = 160 ns, also the DUT's (clk = 10 ns)
    bit            scb_check   = 1;

    function new(string name = "cc");
        super.new(name);
    endfunction

    function void apply_plusargs();
        string s;
        int unsigned v;
        void'($value$plusargs("i2s_slave=%s", slave));
        void'($value$plusargs("i2s_a_clk=%s", a_clk));
        void'($value$plusargs("i2s_b_clk=%s", b_clk));
        if ($value$plusargs("i2s_fmt=%s", s)) begin
            case (s)
                "i2s": fmt = ODVE_I2S_FMT_I2S;
                "lj":  fmt = ODVE_I2S_FMT_LJ;
                "rj":  fmt = ODVE_I2S_FMT_RJ;
                "tdm": fmt = ODVE_I2S_FMT_TDM;
                default: `uvm_fatal("CC", $sformatf("+i2s_fmt=%s: i2s, lj, rj or tdm", s))
            endcase
        end
        if ($value$plusargs("i2s_wlen=%d", v))   wlen = v;
        if ($value$plusargs("i2s_slen=%d", v))   slen = v;
        if ($value$plusargs("i2s_slots=%d", v))  nslots = v;
        if ($value$plusargs("i2s_frames=%d", v)) frames = v;
        if ($test$plusargs("i2s_mono"))          mono = 1;
        if ($value$plusargs("i2s_sck_half=%d", v)) sck_half_ns = v;
        if ($value$plusargs("i2s_inj=%s", s)) begin
            if      (s == "glitch") inj = ODVE_I2S_INJ_WS_GLITCH;
            else if (s == "shift")  inj = ODVE_I2S_INJ_WS_SHIFT;
            else `uvm_fatal("CC", $sformatf("+i2s_inj=%s: glitch or shift", s))
        end
        if (!(slave inside {"dut", "agent"})) `uvm_fatal("CC", $sformatf("+i2s_slave=%s: dut or agent", slave))
        if (!(a_clk inside {"tx", "rx"}))     `uvm_fatal("CC", $sformatf("+i2s_a_clk=%s: tx or rx", a_clk))
        if (!(b_clk inside {"tx", "rx"}))     `uvm_fatal("CC", $sformatf("+i2s_b_clk=%s: tx or rx", b_clk))
        if (sck_half_ns < 40 || sck_half_ns % 10 != 0)
            `uvm_fatal("CC", $sformatf("+i2s_sck_half=%0d: a multiple of the 10 ns clk, >= 40", sck_half_ns))
        if (inj != ODVE_I2S_INJ_NONE && a_clk != "tx")
            `uvm_fatal("CC", "+i2s_inj needs the transmitter agent as port A clock controller (+i2s_a_clk=tx)")
    endfunction

    function bit has_dut();
        return slave == "dut";
    endfunction

    // one frame on the bus, in ns
    function int unsigned frame_ns();
        return nslots * slen * 2 * sck_half_ns;
    endfunction

    function string convert2string();
        return $sformatf("slave=%s a_clk=%s b_clk=%s %s w%0d s%0d x%0d%s frames=%0d %s%s", slave, a_clk, b_clk,
                         fmt.name(), wlen, slen, nslots, mono ? " mono" : "", frames, src.name(),
                         inj == ODVE_I2S_INJ_NONE ? "" : {" inj=", inj.name()});
    endfunction
endclass : cc
