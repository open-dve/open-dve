// Random frames with 0..3 idle frames before each (not back-to-back).
class odve_i2s_gap_seq extends odve_i2s_base_seq;
    `uvm_object_utils(odve_i2s_gap_seq)
    function new(string name = "odve_i2s_gap_seq");
        super.new(name);
        gap_max = 3;
    endfunction
endclass
