// Sequencer of the reactive TAP (cfg.slv_mode == ODVE_JTAG_SLV_SEQ): the
// slave driver drops a request into req_fifo at every Capture-DR and
// Update-DR, the responding sequence answers it in zero time.
class odve_jtag_slv_sqr extends uvm_sequencer #(odve_jtag_item);
    `uvm_component_utils(odve_jtag_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_jtag_item) req_fifo;

    function new(string name = "odve_jtag_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken by uvm_sequencer_param_base
    endfunction
endclass
