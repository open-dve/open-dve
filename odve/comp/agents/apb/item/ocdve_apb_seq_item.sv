class ocdve_apb_seq_item#(parameter type VIF = virtual ocdve_apb_if)  extends uvm_object;
    rand bit[VIF::ADDR_WIDTH-1:0] address;
    rand bit[VIF::DATA_WIDTH-1:0] data;
    rand bit                      slverr;
    rand ocdve_apb_kind_e kind;// == APB_WRITE) ? 1'b1 : 1'b0;

    constraint slverr_c {soft slverr == 1'b0; };
    
    `uvm_object_param_utils_begin(oocdve_apb_seq_item#(VIF))
        `uvm_field_int (address, UVM_DEFAULT)
        `uvm_field_int (data, UVM_DEFAULT)
        `uvm_field_int (slverr, UVM_DEFAULT)
        `uvm_field_enum(ocdve_apb_kind_e, kind, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ocdve_apb_agent_cfg");
        super.new(name);
    endfunction: new
endclass: oocdve_apb_seq_item