// TDM / DSP format: one-SCK frame-sync pulse on WS, MSB of slot 0 one SCK
// later, 4 slots of 32 with 24-bit words (+i2s_slots / +i2s_wlen / +i2s_slen to change).
class i2s_tdm_test extends base_test;
    `uvm_component_utils(i2s_tdm_test)
    function new(string name = "i2s_tdm_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual function void configure();
        tc.fmt    = ODVE_I2S_FMT_TDM;
        tc.nslots = 4;
        tc.wlen   = 24;
        tc.slen   = 32;
    endfunction
endclass
