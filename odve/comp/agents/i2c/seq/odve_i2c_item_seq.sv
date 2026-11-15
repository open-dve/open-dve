// Runs one prepared item (directed traffic, and the transport of layered
// agents such as SMBus): set `item`, start the sequence, read the results
// back from the same item.
class odve_i2c_item_seq extends uvm_sequence #(odve_i2c_item);
    `uvm_object_utils(odve_i2c_item_seq)

    odve_i2c_item item;

    function new(string name = "odve_i2c_item_seq");
        super.new(name);
    endfunction

    virtual task body();
        if (item == null) `uvm_fatal(get_name(), "no item")
        start_item(item);
        finish_item(item);
    endtask
endclass
