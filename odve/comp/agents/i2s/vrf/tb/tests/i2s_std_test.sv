// Philips I2S format (WS low = left, MSB one SCK after the WS edge),
// random stereo frames back-to-back. Word/slot length from +i2s_wlen /
// +i2s_slen (default 16 in 32).
class i2s_std_test extends base_test;
    `uvm_component_utils(i2s_std_test)
    function new(string name = "i2s_std_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual function void configure();
        tc.fmt = ODVE_I2S_FMT_I2S;
    endfunction
endclass
