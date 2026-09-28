class odve_apb_cfg extends uvm_object;
    `uvm_object_utils(odve_apb_cfg)

    bit is_master = 1;
    virtual odve_apb_if vif;

    function new(string name = "odve_apb_cfg");
        super.new(name);
    endfunction
endclass
