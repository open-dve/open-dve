// Mixed reads and writes as user_randomize() picks them.
class odve_apb_rw_seq extends odve_apb_base_seq;
    `uvm_object_utils(odve_apb_rw_seq)
    function new(string name = "odve_apb_rw_seq");
        super.new(name);
    endfunction
endclass
