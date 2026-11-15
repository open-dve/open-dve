// Right-justified format (WS high = left, LSB in the last SCK period of the slot), 24-bit words in 32-bit slots.
class i2s_rj_test extends base_test;
    `uvm_component_utils(i2s_rj_test)
    function new(string name = "i2s_rj_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual function void configure();
        tc.fmt  = ODVE_I2S_FMT_RJ;
        tc.wlen = 24;
        tc.slen = 32;
    endfunction
endclass
