class odve_apb_base_seq extends uvm_sequence#(odve_apb_item);
  odve_apb_item item;
 `uvm_object_utils_begin(odve_apb_base_seq)
    `uvm_object_field (item, UVM_ALL_ON | UVM_NOPACK);
 `uvm_object_utils_end

  function new(string name="odve_apb_base_seq");
     super.new(name);
  endfunction
endclass 

