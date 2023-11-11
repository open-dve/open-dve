class ocdve_apb_agent_cfg extends uvm_object;
    bit     is_master = 1;
    virtual ocdve_apb_if vif;
    `uvm_object_utils_begin(ocdve_apb_agent_cfg)
        `uvm_field_int (is_master, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ocdve_apb_agent_cfg");
        super.new(name);
    endfunction: new
endclass: ocdve_apb_agent_cfg

