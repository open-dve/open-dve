// Frames with 0..3 idle frames before each (not back-to-back): the DUT's
// transmitter underruns and sends idle frames in between.
class i2s_gap_test extends base_test;
    `uvm_component_utils(i2s_gap_test)
    function new(string name = "i2s_gap_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual function odve_i2s_base_seq make_seq();
        return odve_i2s_gap_seq::type_id::create("gaps");
    endfunction
endclass
