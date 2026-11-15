// Connectivity / configuration of the testbench: who plays the JTAG target.
//   +jtag_slave=dut    the single-TAP RTL in vrf/dut (default)
//   +jtag_slave=chain  the RTL daisy chain of two TAPs
//   +jtag_slave=mem    the slave agent, registers inside its driver (autonomous)
//   +jtag_slave=seq    the slave agent, data registers in a responding sequence
//   +jtag_err=oe|ircap fault injection into the slave agent (mem/seq only):
//                      TDO enabled outside Shift / Capture-IR loading 0000
// top.sv reads +jtag_slave too, to route TDO onto the bus.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string slave = "dut";
    string err   = "none";

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("jtag_slave=%s", slave)) slave = "dut";
        if (!(slave inside {"dut", "chain", "mem", "seq"}))
            `uvm_fatal(get_name(), $sformatf("+jtag_slave=%s: expected dut, chain, mem or seq", slave))
        if (!$value$plusargs("jtag_err=%s", err)) err = "none";
        if (!(err inside {"none", "oe", "ircap"}))
            `uvm_fatal(get_name(), $sformatf("+jtag_err=%s: expected none, oe or ircap", err))
        if (err != "none" && !slave_is_agent())
            `uvm_fatal(get_name(), "+jtag_err needs +jtag_slave=mem or seq")
    endfunction

    function bit slave_is_agent();
        return slave inside {"mem", "seq"};
    endfunction

    function int unsigned n_taps();
        return (slave == "chain") ? 2 : 1;
    endfunction

    // the TAPs on the bus, tap[0] nearest TDI - the scoreboard's model
    function bit [31:0] idcode(int unsigned k);
        return 32'h1234_5679 + k * 32'h1000_0000;
    endfunction

    function bit [7:0] pins(int unsigned k);
        return 8'hA5 + 8'(k);
    endfunction
endclass : cc
