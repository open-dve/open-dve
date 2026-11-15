// 8N1, random characters with random idle gaps: the plain echo path.
class basic_test extends base_test;
    `uvm_component_utils(basic_test)

    function new(string name = "basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        phase.raise_objection(this);
        set_format(8, ODVE_UART_PAR_NONE, ODVE_UART_STOP1);
        send(40);
        wait_drain();
        phase.drop_objection(this);
    endtask : run_phase
endclass : basic_test
