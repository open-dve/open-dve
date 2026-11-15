// The transmitter agent in autonomous mode (cfg.src = SRC_GEN): the driver
// makes tc.frames frames itself, no sequence; the scoreboard checks them
// through its sent_port like sequence frames.
class i2s_gen_test extends base_test;
    `uvm_component_utils(i2s_gen_test)
    function new(string name = "i2s_gen_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual function void configure();
        tc.src = ODVE_I2S_SRC_GEN;
    endfunction
endclass
