class odve_jtag_sqr extends uvm_sequencer #(odve_jtag_item);
    `uvm_component_utils(odve_jtag_sqr)

    function new(string name = "odve_jtag_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
