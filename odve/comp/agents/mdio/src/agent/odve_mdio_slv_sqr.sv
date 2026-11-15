// Sequencer of the reactive PHY (cfg.slv_mode == ODVE_MDIO_SLV_SEQ): the
// slave driver drops every decoded frame into req_fifo, the responding
// sequence takes it from there and answers with a response item.
class odve_mdio_slv_sqr extends uvm_sequencer #(odve_mdio_item);
    `uvm_component_utils(odve_mdio_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_mdio_item) req_fifo;

    function new(string name = "odve_mdio_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken by uvm_sequencer_param_base
    endfunction
endclass
