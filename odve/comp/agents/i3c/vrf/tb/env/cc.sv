// Connectivity / configuration of the testbench: which targets are on the bus.
//   +i3c_target=dut    the RTL target in vrf/dut (default)
//   +i3c_target=mem    the target agent alone, registers inside its driver
//   +i3c_target=seq    the target agent alone, registers in a responding sequence
//   +i3c_target=both   RTL target + target agent (MEM): two targets, ENTDAA and
//                      IBI arbitration between them
// top.sv reads the same plusarg to connect (or not) the RTL target's SDA.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string target = "dut";

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("i3c_target=%s", target)) target = "dut";
        if (!(target inside {"dut", "mem", "seq", "both"}))
            `uvm_fatal(get_name(), $sformatf("+i3c_target=%s: expected dut, mem, seq or both", target))
    endfunction

    function bit has_dut();
        return target inside {"dut", "both"};
    endfunction
    function bit has_tgt_agent();
        return target inside {"mem", "seq", "both"};
    endfunction
endclass : cc
