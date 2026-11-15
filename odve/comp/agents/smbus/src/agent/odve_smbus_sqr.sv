class odve_smbus_sqr extends uvm_sequencer #(odve_smbus_item);
    `uvm_component_utils(odve_smbus_sqr)

    function new(string name = "odve_smbus_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
