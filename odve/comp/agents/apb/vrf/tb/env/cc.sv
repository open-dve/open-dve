// Connectivity / configuration of the testbench: who plays the APB slave.
//   +apb_slave=dut   the RTL slave in vrf/dut (default)
//   +apb_slave=mem   the slave agent, memory inside its driver (autonomous)
//   +apb_slave=seq   the slave agent, memory in a responding sequence
//   +apb_slave=cov   the functional-coverage emulation block (odve_cov_emu)
// top.sv reads the same plusarg to route the slave signals onto the bus.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string slave = "dut";

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("apb_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "mem", "seq", "cov"}))
            `uvm_fatal(get_name(), $sformatf("+apb_slave=%s: expected dut, mem, seq or cov", slave))
    endfunction

    function bit slave_is_agent();
        return slave inside {"mem", "seq"};
    endfunction

    // The scoreboard models the register file; the coverage block has
    // read-only counters that change under traffic, checked by its own
    // readback sequence instead.
    function bit has_scb();
        return slave != "cov";
    endfunction
endclass : cc
