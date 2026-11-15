// Master sequencer; cfg lets sequences draw data for the link's format.
class odve_uart_sqr extends uvm_sequencer #(odve_uart_item);
    `uvm_component_utils(odve_uart_sqr)

    odve_uart_cfg cfg;

    function new(string name = "odve_uart_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
