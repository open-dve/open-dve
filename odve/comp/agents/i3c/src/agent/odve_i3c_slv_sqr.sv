// Sequencer of the reactive target (cfg.slv_mode == ODVE_I3C_SLV_SEQ): the
// driver drops every private-transfer byte request into req_fifo, the
// responding sequence gets it from there and answers with a response item.
class odve_i3c_slv_sqr extends uvm_sequencer #(odve_i3c_item);
    `uvm_component_utils(odve_i3c_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_i3c_item) req_fifo;

    function new(string name = "odve_i3c_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken by uvm_sequencer_param_base
    endfunction
endclass
