class odve_apb_read_seq extends odve_apb_base_seq;
    `uvm_object_utils(odve_apb_read_seq)
    function new(string name = "odve_apb_read_seq");
        super.new(name);
    endfunction
    virtual function int dir();
        return 0;
    endfunction
endclass
