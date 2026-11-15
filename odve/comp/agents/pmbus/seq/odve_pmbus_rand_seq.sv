// n random PMBus commands (odve_pmbus_item::user_randomize()): reads and
// writes of the device's commands across both pages, PEC on p_pec %, and
// p_invalid % unsupported codes / invalid data.
class odve_pmbus_rand_seq extends uvm_sequence #(odve_pmbus_item);
    `uvm_object_utils(odve_pmbus_rand_seq)

    int unsigned n         = 40;
    bit [6:0]    addr      = 7'h40;
    int unsigned p_pec     = 50;
    int unsigned p_invalid = 5;
    bit [7:0]    cmds[$];
    odve_rand    rng;

    function new(string name = "odve_pmbus_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_pmbus_item item;
        if (rng == null) rng = new(get_full_name());
        repeat (n) begin
            item = odve_pmbus_item::type_id::create("item");
            item.rng       = rng.spawn();
            item.p_pec     = p_pec;
            item.p_invalid = p_invalid;
            item.cmds      = cmds;
            `odve_rand(item)
            item.addr = addr;
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
