class odve_i2s_sqr extends uvm_sequencer #(odve_i2s_item);
    `uvm_component_utils(odve_i2s_sqr)

    odve_i2s_cfg cfg;   // set by the agent; sequences copy the frame shape from it

    function new(string name = "odve_i2s_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
