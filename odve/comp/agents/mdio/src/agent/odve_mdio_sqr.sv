class odve_mdio_sqr extends uvm_sequencer #(odve_mdio_item);
    `uvm_component_utils(odve_mdio_sqr)

    function new(string name = "odve_mdio_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
