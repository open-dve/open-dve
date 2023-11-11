class ocdve_apb_master_driver extends ocdve_apb_driver_base;
    `uvm_component_utils(ocdve_apb_master_driver)

    //protected virtual ocdve_apb_if vif; moved to ocdve_apb_driver_base

    function new(string name = "ocdve_apb_master_driver", uvm_component parent);
        super.new(name, parent);
    endfunction: new

    //extern virtual task run_phase(uvm_phase phase); moved to ocdve_apb_driver_base
    extern virtual task init_signals();
    extern virtual task get_and_drive();
    //extern function void set_cfg(ocdve_apb_agent_cfg cfg); moved to ocdve_apb_driver_base
endclass : ocdve_apb_master_driver

task ocdve_apb_master_driver::get_and_drive();
    bit is_next_tr_availibale;
    forever begin
        is_next_tr_availibale = seq_item_port.has_do_available();
        seq_item_port.get_next_item(req);
        if(!is_next_tr_availibale) @(posedge vif.clk); // if it's not back to back access otherwise we need one more sync clock
        // Idle phase
        // TODO: add delay
        // Setup phase
        vif.paddr_l   <= req.address;
        vif.psel_l    <= 1'b1;
        vif.penable_l <= 1'b0;
        vif.pwrite_l  <= (req.kind == APB_WRITE) ? 1'b1 : 1'b0;
        vif.pwdata_l  <= req.data;

        @(posedge vif.clk);
        // Access phase
        vif.penable_l <= 1'b1;
        @(posedge vif.clk iff vif.pready === 1'b1);
        if(req.kind == APB_WRITE)
            req.data = vif.prdata;
        vif.psel_l    <= 1'b0;
        vif.penable_l <= 1'b0;
    end    
endtask: get_and_drive

task ocdve_apb_master_driver::init_signals();
    vif.paddr_l   <= '0;
    vif.psel_l    <= 1'b0;
    vif.penable_l <= 1'b0;
    vif.pwrite_l  <= 1'b0;
    vif.pwdata_l  <= '0;
    @(posedge vif.clk iff vif.reset_n === 1'b1);
endtask: init_signals

//task ocdve_apb_master_driver::run_phase(puvm_phase phase);
//    super.run_phase(phase);
//    @(negedge vif.reset_n or posedge vif.clk iff vif.reset_n === 1'b0);
//    forever begin
//        init_signals();
//        fork
//            get_and_drive();
//            @(negedge vif.reset_n);
//        join_any
//        disable fork;
//    end
//endtask: run_phase
//
//function void ocdve_apb_master_driver::set_cfg(ocdve_apb_agent_cfg cfg);
//    vif = cfg.vif;
//endfunction