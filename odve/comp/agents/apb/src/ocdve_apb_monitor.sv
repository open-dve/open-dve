class ocdve_apb_monitor#(parameter type VIF = virtual ocdve_apb_if)  extends ocdve_common_monitor;
    `uvm_component_param_utils(ocdve_apb_monitor#(VIF))
    protected VIF vif;

    function new(string name = "ocdve_apb_monitor", uvm_component parent);
        super.new(name, parent);
    endfunction: new

    extern virtual task run_phase(uvm_phase phase);
    extern function void set_cfg(ocdve_apb_agent_cfg#(VIF) cfg);
endclass : ocdve_apb_monitor

task ocdve_apb_monitor::run_phase(uvm_phase phase);
    ocdve_apb_seq_item#(VIF) tr_clone, tr = ocdve_apb_seq_item#(VIF)::type_id::create("apb_tr"); 
    super.run_phase(phase);
    forever begin
        @(posedge vif.clk iff vif.pready === 1'b1 && vif.psel === 1'b1 && vif.penable === 1'b1 && vif.reset_n === 1'b0);
        $cast(tr_clone, tr);
        tr_clone.slverr = vif.pslverr;
        if(vif.pwrite) begin
            tr_clone.data = vif.pwdata;
            tr_clone.kind = APB_WRITE;
        end else begin
            tr_clone.data = vif.prdata;
            tr_clone.kind = APB_READ;
        end
        item_collected_port.write(tr_clone);
    end
endtask : run_phase

function void ocdve_apb_monitor::set_cfg(ocdve_apb_agent_cfg#(VIF) cfg);
    vif = cfg.vif;
endfunction