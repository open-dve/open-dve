class ocdve_apb_agent#(parameter type VIF = virtual ocdve_apb_if) extends ocdve_common_component;
    `uvm_component_param_utils(ocdve_apb_agent#(VIF))
    typedef uvm_sequencer#(ocdve_apb_seq_item#(VIF)) ocdve_apb_sequencer;

    uvm_analysis_port #(ocdve_apb_seq_item#(VIF)) ap;

    ocdve_apb_agent_cfg#(VIF)   config_o;
    ocdve_common_driver#(VIF)   driver; // Master or slave, depends on config_o
    ocdve_apb_monitor#(VIF)     monitor;
    ocdve_apb_sequencer#(VIF)   sequencer;

    function new(string name = "ocdve_apb_agent", uvm_component parent);
        super.new(name, parent);
    endfunction: new

    extern function void build_phase(uvm_phase phase);
    extern function void connect_phase(uvm_phase phase);
endclass: ocdve_apb_agent

function void ocdve_apb_agent::build_phase(uvm_phase phase);
    if(!uvm_config_db#(ocdve_apb_agent_cfg#(VIF))::get(this, "", "cfg", config_o)) begin
        `uvm_fatal(get_name(), "No config object")
    end
    if(config_o.vif == null && !uvm_config_db#(VIF)::get(this, "", "apb_vif", config_o.vif)) begin
        `uvm_fatal(get_name(), "No VIF")
    end
    if(config_o.is_master) begin
        driver   = ocdve_apb_master_driver#(VIF)::type_id::create("driver", this);
    end else begin
        driver   = ocdve_apb_slave_driver#(VIF)::type_id::create("driver", this);
    end
    sequencer = ocdve_apb_sequencer#(VIF)::type_id::create("sequencer", this);
    monitor   = ocdve_apb_monitor#(VIF)::type_id::create("monitor", this);
    driver.set_cfg(config_o);
    monitor.set_cfg(config_o);

    ap = uvm_analysis_port #(ocdve_apb_seq_item#(VIF))::type_id::create("ap", this); 
endfunction : build_phase

function void ocdve_apb_agent::connect_phase(uvm_phase phase);
    monitor.item_collected_port.connect(ap);
    driver.seq_item_port.connect(sequencer.seq_item_export);
endfunction : connect_phase    