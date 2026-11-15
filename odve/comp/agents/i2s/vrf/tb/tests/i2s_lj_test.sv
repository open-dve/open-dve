// Left-justified format (WS high = left, MSB in the WS-edge SCK period), 24-bit words in 32-bit slots.
class i2s_lj_test extends base_test;
    `uvm_component_utils(i2s_lj_test)
    function new(string name = "i2s_lj_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual function void configure();
        tc.fmt  = ODVE_I2S_FMT_LJ;
        tc.wlen = 24;
        tc.slen = 32;
    endfunction
endclass
