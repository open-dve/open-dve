// Sequencer of the reactive slave (cfg.slv_mode == ODVE_I2C_SLV_SEQ): the
// driver drops every target event into req_fifo, the responding sequence
// takes it from there and answers with the same item, filled in.
class odve_i2c_slv_sqr extends uvm_sequencer #(odve_i2c_slv_item);
    `uvm_component_utils(odve_i2c_slv_sqr)

    uvm_tlm_analysis_fifo #(odve_i2c_slv_item) req_fifo;

    function new(string name = "odve_i2c_slv_sqr", uvm_component parent = null);
        super.new(name, parent);
        req_fifo = new("slv_req_fifo", this);   // "req_fifo" is taken by uvm_sequencer_param_base
    endfunction
endclass
