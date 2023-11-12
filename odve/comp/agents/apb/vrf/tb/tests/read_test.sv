class read_test extends uvm_test;
    `uvm_component_utils(read_test)

    function new(string name = "red_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info(get_name(),"RUN TEST", UVM_NONE)
    endtask : run_phase
endclass : read_test

