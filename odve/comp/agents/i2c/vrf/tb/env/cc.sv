// Connectivity / configuration of the testbench: who plays the I2C target.
//   +i2c_slave=dut   the RTL target in vrf/dut (default)
//   +i2c_slave=mem   the slave agent, register model inside its driver
//   +i2c_slave=seq   the slave agent, register model in a responding sequence
// top.sv reads the same plusarg to connect or disconnect the DUT.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string slave = "dut";

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("i2c_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "mem", "seq"}))
            `uvm_fatal(get_name(), $sformatf("+i2c_slave=%s: expected dut, mem or seq", slave))
    endfunction

    function bit slave_is_agent();
        return slave != "dut";
    endfunction
endclass : cc
