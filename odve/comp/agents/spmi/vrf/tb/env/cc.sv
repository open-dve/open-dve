// Testbench configuration: who plays the primary slave (SID 5).
//   +spmi_slave=dut   the RTL slave dut_i (default)
//   +spmi_slave=mem   the slave agent, registers inside its driver
//   +spmi_slave=seq   the slave agent, registers in a responding sequence
// top.sv reads the same plusarg to route the SDATA drivers. The secondary
// slave (SID A) is always the RTL slave dut2_i.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string       slave     = "dut";
    bit [3:0]    sid_prim  = 4'h5;
    bit [3:0]    sid_sec   = 4'hA;
    int unsigned nregs     = 64;

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("spmi_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "mem", "seq"}))
            `uvm_fatal(get_name(), $sformatf("+spmi_slave=%s: expected dut, mem or seq", slave))
    endfunction

    function bit slave_is_agent();
        return slave inside {"mem", "seq"};
    endfunction
endclass : cc
