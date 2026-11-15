// Connectivity / configuration of the testbench: who answers the master.
//   +uart_slave=dut   the RTL echo device in vrf/dut (default)
//   +uart_slave=mem   the slave agent, echo FIFO inside its driver (autonomous)
//   +uart_slave=seq   the slave agent, answers from a responding sequence
// top.sv reads the same plusarg to route rxd / cts_n.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string slave = "dut";

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("uart_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "mem", "seq"}))
            `uvm_fatal(get_name(), $sformatf("+uart_slave=%s: expected dut, mem or seq", slave))
    endfunction

    function bit slave_is_agent();
        return slave != "dut";
    endfunction
endclass : cc
