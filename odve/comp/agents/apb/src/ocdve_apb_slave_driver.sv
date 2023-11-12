class ocdve_apb_slave_driver#(parameter type VIF = virtual ocdve_apb_if)  extends ocdve_apb_driver_base#(VIF);
    `uvm_component_param_utils(ocdve_apb_slave_driver#(VIF))

    function new(string name = "ocdve_apb_slave_driver", uvm_component parent);
        super.new(name, parent);
    endfunction: new

    extern virtual task init_signals();
    extern virtual task get_and_drive();
endclass : ocdve_apb_slave_driver

task ocdve_apb_master_driver::get_and_drive();
    forever begin
        seq_item_port.get_next_item(req);
        @(posedge vif.clk);
        // TODO: 
        seq_item_port.item_done(req);
    end    
endtask: get_and_drive

task ocdve_apb_master_driver::init_signals();
    vif.pready_l  <= 1'b0;
    vif.prdata_l  <= '0;
    vif.pslverr_l <= 1'b0;
    @(posedge vif.clk iff vif.reset_n === 1'b1);
endtask: init_signals