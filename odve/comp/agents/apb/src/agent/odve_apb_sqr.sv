class odve_apb_sqr extends uvm_sequencer #(odve_apb_item);
    `uvm_component_utils(odve_apb_sqr)

    function new(string name = "odve_apb_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
