// Sequencer of the reactive slave (cfg.slv_mode == ODVE_UART_SLV_SEQ): the
// driver drops every good character it receives into req_fifo, the
// responding sequence gets it from there and answers with the item to send
// back (kind NONE: send nothing).
class odve_uart_slv_sqr extends uvm_sequencer #(odve_uart_item);
    `uvm_component_utils(odve_uart_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_uart_item) req_fifo;
    odve_uart_cfg cfg;

    function new(string name = "odve_uart_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken by uvm_sequencer_param_base
    endfunction
endclass
