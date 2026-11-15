// Master sequencer. Carries the agent cfg so sequences can read the selected
// slave's word width (p_sequencer.cfg.dev[cs]).
class odve_spi_sqr extends uvm_sequencer #(odve_spi_item);
    `uvm_component_utils(odve_spi_sqr)

    odve_spi_cfg cfg;

    function new(string name = "odve_spi_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
