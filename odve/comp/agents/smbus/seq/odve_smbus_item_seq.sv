// Runs one prepared SMBus message; the results come back in `item`.
class odve_smbus_item_seq extends uvm_sequence #(odve_smbus_item);
    `uvm_object_utils(odve_smbus_item_seq)

    odve_smbus_item item;

    function new(string name = "odve_smbus_item_seq");
        super.new(name);
    endfunction

    virtual task body();
        if (item == null) `uvm_fatal(get_name(), "no item")
        start_item(item);
        finish_item(item);
    endtask
endclass
