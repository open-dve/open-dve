// Who plays the PMBus device:
//   +pmbus_slave=dut   the RTL device in vrf/dut (default)
//   +pmbus_slave=mem   the slave agent, PMBus model inside the i2c slave driver
//   +pmbus_slave=seq   the slave agent, PMBus model in a responding sequence
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string slave = "dut";

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("pmbus_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "mem", "seq"}))
            `uvm_fatal(get_name(), $sformatf("+pmbus_slave=%s: expected dut, mem or seq", slave))
    endfunction

    function bit slave_is_agent();
        return slave != "dut";
    endfunction
endclass : cc
