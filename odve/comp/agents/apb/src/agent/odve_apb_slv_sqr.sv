// Sequencer of the reactive slave (cfg.slv_mode == ODVE_APB_SLV_SEQ): the
// driver drops every observed request into req_fifo, the responding sequence
// gets it from there and answers with a response item.
class odve_apb_slv_sqr extends uvm_sequencer #(odve_apb_item);
    `uvm_component_utils(odve_apb_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_apb_item) req_fifo;

    function new(string name = "odve_apb_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken: uvm_sequencer_param_base names its own m_req_fifo so
    endfunction
endclass
