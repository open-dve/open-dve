class ocdve_apb_agent_cfg#(parameter type VIF = virtual ocdve_apb_if)  extends uvm_object;
    bit     is_master = 1;
    VIF     vif;
    `uvm_object_param_utils_begin(ocdve_apb_agent_cfg#(VIF))
        `uvm_field_int (is_master, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ocdve_apb_agent_cfg");
        super.new(name);
    endfunction: new
endclass: ocdve_apb_agent_cfg

