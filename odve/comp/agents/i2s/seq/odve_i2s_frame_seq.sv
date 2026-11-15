// Random frames, back-to-back (no idle frame in between).
class odve_i2s_frame_seq extends odve_i2s_base_seq;
    `uvm_object_utils(odve_i2s_frame_seq)
    function new(string name = "odve_i2s_frame_seq");
        super.new(name);
    endfunction
endclass
