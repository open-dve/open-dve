class odve_spmi_sqr extends uvm_sequencer #(odve_spmi_item);
    `uvm_component_utils(odve_spmi_sqr)

    function new(string name = "odve_spmi_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
