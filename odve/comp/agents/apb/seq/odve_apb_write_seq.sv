class odve_apb_write_seq extends odve_apb_base_seq;
    `uvm_object_utils(odve_apb_write_seq)
    function new(string name = "odve_apb_write_seq");
        super.new(name);
    endfunction
    virtual function int dir();
        return 1;
    endfunction
endclass
