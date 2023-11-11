class ocdve_apb_monitor extends ocdve_common_driver;
    `uvm_component_utils(ocdve_apb_monitor)

    protected virtual ocdve_apb_if vif;

    function new(string name = "ocdve_apb_monitor", uvm_component parent);
        super.new(name, parent);
    endfunction: new

    extern function void set_cfg(ocdve_apb_agent_cfg cfg);
endclass : ocdve_apb_monitor

function void ocdve_apb_monitor::set_cfg(ocdve_apb_agent_cfg cfg);
    vif = cfg.vif;
endfunction