// Connectivity / configuration of the testbench.
//   +qspi_slave=dut   the RTL flash in vrf/dut (default)
//   +qspi_slave=mem   the slave agent, flash model inside its driver
//   +qspi_slave=seq   the slave agent, flash model in a responding sequence
//   +qspi_mode=0|3    SPI mode of the bus (sclk idle level), default 0
// top.sv reads +qspi_slave too, to keep the RTL flash deselected.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string slave = "dut";
    int    mode  = 0;

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("qspi_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "mem", "seq"}))
            `uvm_fatal(get_name(), $sformatf("+qspi_slave=%s: expected dut, mem or seq", slave))
        if (!$value$plusargs("qspi_mode=%d", mode)) mode = 0;
        if (!(mode inside {0, 3}))
            `uvm_fatal(get_name(), $sformatf("+qspi_mode=%0d: expected 0 or 3", mode))
    endfunction

    function bit slave_is_agent();
        return slave inside {"mem", "seq"};
    endfunction
endclass : cc
