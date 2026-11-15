// Sequencer of the reactive slave (cfg.slv_mode == ODVE_QSPI_SLV_SEQ): the
// driver drops every request into req_fifo, the responding sequence gets it
// from there and answers (odve_qspi_slv_rsp_seq).
class odve_qspi_slv_sqr extends uvm_sequencer #(odve_qspi_item);
    `uvm_component_utils(odve_qspi_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_qspi_item) req_fifo;
    odve_qspi_cfg cfg;

    function new(string name = "odve_qspi_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken by uvm_sequencer_param_base
    endfunction
endclass
