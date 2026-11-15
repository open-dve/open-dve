// Boundary sample values (0, +full scale, -full scale, +1, -1): the DUT's
// negation must saturate -full scale to +full scale.
class i2s_corner_test extends base_test;
    `uvm_component_utils(i2s_corner_test)
    function new(string name = "i2s_corner_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    virtual function void configure();
        tc.frames = 32;
    endfunction
    virtual function odve_i2s_base_seq make_seq();
        return odve_i2s_corner_seq::type_id::create("corner");
    endfunction
endclass
