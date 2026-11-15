// Connectivity / configuration of the testbench: who answers the chip selects.
//   +spi_slave=dut   the two RTL slaves in vrf/dut (default)
//   +spi_slave=mem   two slave agents, register model inside their drivers
//   +spi_slave=seq   two slave agents, register model in a responding sequence
// top.sv reads the same plusarg to keep the RTL slaves deselected.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string slave = "dut";

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("spi_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "mem", "seq"}))
            `uvm_fatal(get_name(), $sformatf("+spi_slave=%s: expected dut, mem or seq", slave))
    endfunction

    function bit slave_is_agent();
        return slave inside {"mem", "seq"};
    endfunction
endclass : cc
