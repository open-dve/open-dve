// Master sequencer. Carries the agent cfg so sequences can read the bus
// mode (p_sequencer.cfg.bus.qpi) and the flash size.
class odve_qspi_sqr extends uvm_sequencer #(odve_qspi_item);
    `uvm_component_utils(odve_qspi_sqr)

    odve_qspi_cfg cfg;

    function new(string name = "odve_qspi_sqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
