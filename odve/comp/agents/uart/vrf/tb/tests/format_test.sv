// Every frame format the 16550 LCR allows: 5..8 data bits x no/even/odd/
// mark/space parity x 1 stop bit and 1.5 (5 bits) / 2 (6..8 bits) stop bits,
// 40 formats, a few random characters and the edge patterns in each.
class format_test extends base_test;
    `uvm_component_utils(format_test)

    function new(string name = "format_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        odve_uart_parity_e par;
        super.run_phase(phase);
        phase.raise_objection(this);
        for (int bits = 5; bits <= 8; bits++)
            for (int p = 0; p < 5; p++)
                for (int s = 0; s < 2; s++) begin
                    par = odve_uart_parity_e'(p);
                    set_format(bits, par, s == 0 ? ODVE_UART_STOP1 : bits == 5 ? ODVE_UART_STOP1_5 : ODVE_UART_STOP2);
                    send(3);
                    send_pattern(1);
                    wait_drain();
                end
        phase.drop_objection(this);
    endtask : run_phase
endclass : format_test
