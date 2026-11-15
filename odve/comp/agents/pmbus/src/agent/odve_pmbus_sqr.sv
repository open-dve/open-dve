class odve_pmbus_sqr extends uvm_sequencer #(odve_pmbus_item);
    `uvm_component_utils(odve_pmbus_sqr)

    function new(string name = "odve_pmbus_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
