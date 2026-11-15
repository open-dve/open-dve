// Connectivity / configuration of the testbench: who plays the PHY(s).
//   +mdio_slave=dut    the RTL PHY in vrf/dut at PHY/port address 1 (default)
//   +mdio_slave=mem    the slave agent, register model in its driver, PHYs/ports 1 and 2
//   +mdio_slave=seq    the slave agent, register model in a responding sequence, 1 and 2
//   +mdio_slave=multi  both on one bus: the RTL PHY at 1, the slave agent (mem) at 2 and 3
// top.sv reads the same plusarg to connect (or not) the DUT's MDIO output.
class cc extends uvm_component;
    `uvm_component_utils(cc)

    string    slave = "dut";
    bit [4:0] addrs[$];        // every responding PHY/port address on the bus
    bit [4:0] agent_addrs[$];  // the ones the slave agent plays

    function new(string name = "cc", uvm_component parent = null);
        super.new(name, parent);
        if (!$value$plusargs("mdio_slave=%s", slave)) slave = "dut";
        case (slave)
            "dut":        begin addrs = '{5'd1};             agent_addrs = {};            end
            "mem", "seq": begin addrs = '{5'd1, 5'd2};       agent_addrs = '{5'd1, 5'd2}; end
            "multi":      begin addrs = '{5'd1, 5'd2, 5'd3}; agent_addrs = '{5'd2, 5'd3}; end
            default: `uvm_fatal(get_name(), $sformatf("+mdio_slave=%s: expected dut, mem, seq or multi", slave))
        endcase
    endfunction

    function bit has_slave_agent();
        return agent_addrs.size() != 0;
    endfunction

    // an address no PHY answers
    function bit [4:0] miss_addr(int unsigned i = 0);
        bit [4:0] a = 5'd31 - 5'(i);
        foreach (addrs[k]) if (addrs[k] == a) return 5'd0;
        return a;
    endfunction
endclass : cc
