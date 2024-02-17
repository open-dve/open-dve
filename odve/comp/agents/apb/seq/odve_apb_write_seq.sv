class odve_apb_write_seq extends odve_apb_base_seq;
  `uvm_object_utils(odve_apb_write_seq)
  function new(string name="odve_apb_write_seq");
    super.new(name);
  endfunction

  virtual task body();
    repeat (20) begin
      item = new("item"); //apb_item::type_id::create("item");
      `odve_rand(item);
      start_item(item);
      finish_item(item);
    end
  endtask
endclass 