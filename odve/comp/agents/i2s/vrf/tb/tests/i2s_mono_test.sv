// Mono: the same sample in both channels of an I2S frame (the monitor checks left == right).
class i2s_mono_test extends base_test;
    `uvm_component_utils(i2s_mono_test)
    function new(string name = "i2s_mono_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual function void configure();
        tc.fmt  = ODVE_I2S_FMT_I2S;
        tc.mono = 1;
    endfunction
endclass
