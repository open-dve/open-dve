// Base of the agent's sequences: n items, values from `odve_rand (plain
// $urandom in odve_apb_item::user_randomize), out-of-range addresses only
// when allow_oor is set.
class odve_apb_base_seq extends uvm_sequence #(odve_apb_item);
    `uvm_object_utils(odve_apb_base_seq)

    int unsigned n         = 8;
    bit          allow_oor = 0;

    function new(string name = "odve_apb_base_seq");
        super.new(name);
    endfunction

    // -1 = keep what user_randomize chose, 0 = read, 1 = write
    virtual function int dir();
        return -1;
    endfunction

    virtual task body();
        odve_apb_item item;
        repeat (n) begin
            item = odve_apb_item::type_id::create("item");
            item.allow_oor = allow_oor;
            `odve_rand(item)
            if (dir() >= 0) item.write = dir();
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
