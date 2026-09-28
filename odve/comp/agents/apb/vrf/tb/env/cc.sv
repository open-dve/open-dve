// Connectivity / configuration component: nothing to configure yet.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass : cc
