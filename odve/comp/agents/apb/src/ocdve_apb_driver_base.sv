class ocdve_apb_driver_base extends ocdve_common_driver#(ocdve_apb_seq_item);
    protected virtual ocdve_apb_if vif;

    function new(string name = "ocdve_apb_driver_base", uvm_component parent);
        super.new(name, parent);
    endfunction: new

    extern virtual task run_phase(uvm_phase phase);
    pure   virtual task init_signals();
    pure   virtual task get_and_drive();
    extern function void set_cfg(ocdve_apb_agent_cfg cfg);
endclass : ocdve_apb_driver_base

task ocdve_apb_driver_base::run_phase(puvm_phase phase);
    super.run_phase(phase);
    @(negedge vif.reset_n or posedge vif.clk iff vif.reset_n === 1'b0);
    forever begin
        init_signals();
        fork
            get_and_drive();
            @(negedge vif.reset_n);
        join_any
        disable fork;
    end
endtask: run_phase

function void ocdve_apb_driver_base::set_cfg(ocdve_apb_agent_cfg cfg);
    vif = cfg.vif;
endfunction