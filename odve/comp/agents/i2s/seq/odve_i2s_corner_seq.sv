// Boundary sample values only: zero, +full scale, -full scale, +1/-1
// (the DUT's negation saturates -full scale).
class odve_i2s_corner_seq extends odve_i2s_base_seq;
    `uvm_object_utils(odve_i2s_corner_seq)
    function new(string name = "odve_i2s_corner_seq");
        super.new(name);
        w_val = '{0, 25, 25, 25, 25};
    endfunction
endclass
