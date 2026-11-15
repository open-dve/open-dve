// Baud-rate mismatch within tolerance: the master transmits 3.1 % slow
// (33 clk/bit) and 3.1 % fast (31 clk/bit) against the nominal 32 the
// receivers (RTL, slave agent, monitor) sample with, back to back, in the
// longest frame (8E2: 12 bits) and in 8N1 / 5M1.5. The echo comes back at
// the nominal rate.
class baud_test extends base_test;
    `uvm_component_utils(baud_test)

    function new(string name = "baud_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        int unsigned rates[2] = '{33, 31};
        super.run_phase(phase);
        phase.raise_objection(this);
        foreach (rates[i]) begin
            env_o.cfg.tx_bit_clks = rates[i];
            `uvm_info(get_name(), $sformatf("master transmits at %0d clk/bit, receivers sample at %0d", rates[i], env_o.cfg.bit_clks), UVM_LOW)
            set_format(8, ODVE_UART_PAR_EVEN, ODVE_UART_STOP2);
            send_pattern(0);
            send(32, 0);
            wait_drain();
            set_format(8, ODVE_UART_PAR_NONE, ODVE_UART_STOP1);
            send(32, 0);
            wait_drain();
            set_format(5, ODVE_UART_PAR_MARK, ODVE_UART_STOP1_5);
            send(16, 0);
            wait_drain();
        end
        env_o.cfg.tx_bit_clks = 0;
        phase.drop_objection(this);
    endtask : run_phase
endclass : baud_test
