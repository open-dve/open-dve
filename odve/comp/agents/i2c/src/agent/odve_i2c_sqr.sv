class odve_i2c_sqr extends uvm_sequencer #(odve_i2c_item);
    `uvm_component_utils(odve_i2c_sqr)

    function new(string name = "odve_i2c_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
