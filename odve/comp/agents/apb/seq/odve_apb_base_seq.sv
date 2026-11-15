// Base of the agent's sequences: n items, values from `odve_rand (an
// odve_rand stream per sequence, one spawned stream per item; $urandom
// instead when built with ODVE_USE_URANDOM - see odve_apb_item.sv),
// out-of-range addresses only when allow_oor is set.
class odve_apb_base_seq extends uvm_sequence #(odve_apb_item);
    `uvm_object_utils(odve_apb_base_seq)

    int unsigned n         = 8;
    bit          allow_oor = 0;
    odve_rand    rng;               // the sequence's stream; null = one named after the sequence

    function new(string name = "odve_apb_base_seq");
        super.new(name);
    endfunction

    // -1 = keep what user_randomize chose, 0 = read, 1 = write
    virtual function int dir();
        return -1;
    endfunction

    virtual task body();
        odve_apb_item item;
        if (rng == null) rng = new(get_full_name());
        repeat (n) begin
            item = odve_apb_item::type_id::create("item");
            item.allow_oor = allow_oor;
            item.rng       = rng.spawn();
            `odve_rand(item)
            if (dir() >= 0) item.write = dir();
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
