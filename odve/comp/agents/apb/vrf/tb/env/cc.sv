// Connectivity / configuration of the testbench: who plays the APB slave.
//   +apb_slave=dut   the RTL slave in vrf/dut (default)
//   +apb_slave=mem   the slave agent, memory inside its driver (autonomous)
//   +apb_slave=seq   the slave agent, memory in a responding sequence
// top.sv reads the same plusarg to route the slave signals onto the bus.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string slave = "dut";

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("apb_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "mem", "seq"}))
            `uvm_fatal(get_name(), $sformatf("+apb_slave=%s: expected dut, mem or seq", slave))
    endfunction

    function bit slave_is_agent();
        return slave != "dut";
    endfunction
endclass : cc
