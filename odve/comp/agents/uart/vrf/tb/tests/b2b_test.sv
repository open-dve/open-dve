// Back-to-back characters (no idle between stop and next start bit) in the
// shortest and longest frames: the receiver must find each start bit right
// after the stop bit(s), the echo keeps pace at the same baud rate.
class b2b_test extends base_test;
    `uvm_component_utils(b2b_test)

    function new(string name = "b2b_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        set_format(8, ODVE_UART_PAR_EVEN, ODVE_UART_STOP2);
        send_pattern(0);
        send(48, 0);
        wait_drain();
        set_format(5, ODVE_UART_PAR_NONE, ODVE_UART_STOP1);
        send_pattern(0);
        send(48, 0);
        wait_drain();
        set_format(7, ODVE_UART_PAR_ODD, ODVE_UART_STOP1);
        send(48, 0);
        wait_drain();
        phase.drop_objection(this);
    endtask : run_phase
endclass : b2b_test
