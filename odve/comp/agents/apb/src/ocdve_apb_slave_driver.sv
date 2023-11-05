class ocdve_apb_slave_driver extends ocdve_apb_driver_base;
    `uvm_component_utils(ocdve_apb_slave_driver)

    function new(string name = "ocdve_apb_slave_driver", uvm_component parent);
        super.new(name, parent);
    endfunction: new

    //extern virtual task run_phase(uvm_phase phase);
    extern virtual task init_signals();
    extern virtual task get_and_drive();
    //extern function void set_cfg(ocdve_apb_agent_cfg cfg);
endclass : ocdve_apb_slave_driver

task ocdve_apb_master_driver::get_and_drive();
    forever begin
        seq_item_port.get_next_item(req);
        @(posedge vif.clk);
        // TODO: 
    end    
endtask: get_and_drive

task ocdve_apb_master_driver::init_signals();
    vif.pready_l  <= 1'b0;
    vif.prdata_l  <= '0;
    vif.pslverr_l <= 1'b0;
    @(posedge vif.clk iff vif.reset_n === 1'b1);
endtask: init_signals