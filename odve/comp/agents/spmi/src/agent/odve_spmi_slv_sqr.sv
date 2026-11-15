// Sequencer of the reactive slave (cfg.slv_mode == ODVE_SPMI_SLV_SEQ): the
// slave driver drops every decoded request into req_fifo (a read once its
// address is known, a write once its data frames are in, a PM command once
// its command frame is), the responding sequence gets it from there and
// answers with a response item (read data and NRF mask; for the others the
// `ack` the slave sends, ANDed with its parity verdict).
class odve_spmi_slv_sqr extends uvm_sequencer #(odve_spmi_item);
    `uvm_component_utils(odve_spmi_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_spmi_item) req_fifo;

    function new(string name = "odve_spmi_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken by uvm_sequencer_param_base
    endfunction
endclass
