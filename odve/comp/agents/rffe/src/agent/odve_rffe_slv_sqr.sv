// Sequencer of the reactive slave (cfg.slv_mode == ODVE_RFFE_SLV_SEQ): the
// slave driver drops every decoded request into req_fifo (a read once its
// address is known, a write once its data frames are in), the responding
// sequence gets it from there and answers with a response item (read data
// and NRF mask; for a write, an empty acknowledgement of the handshake).
class odve_rffe_slv_sqr extends uvm_sequencer #(odve_rffe_item);
    `uvm_component_utils(odve_rffe_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_rffe_item) req_fifo;

    function new(string name = "odve_rffe_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken by uvm_sequencer_param_base
    endfunction
endclass
