// n register-style transfers drawn by odve_i2c_item::user_randomize() from
// this sequence's odve_rand stream; the knobs are copied into each item.
class odve_i2c_rand_seq extends uvm_sequence #(odve_i2c_item);
    `uvm_object_utils(odve_i2c_rand_seq)

    int unsigned n          = 8;
    bit [6:0]    tgt_addr7  = 7'h50;
    bit [9:0]    tgt_addr10 = 10'h2A5;
    int unsigned p_addr10   = 0;
    int unsigned p_bad_addr = 0;
    int unsigned p_bad_ptr  = 0;
    int unsigned nregs      = 16;
    int unsigned max_wr     = 8;
    int unsigned max_rd     = 8;
    int unsigned w_kind[]   = '{1, 1, 1};
    odve_rand    rng;

    function new(string name = "odve_i2c_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_i2c_item item;
        if (rng == null) rng = new(get_full_name());
        repeat (n) begin
            item = odve_i2c_item::type_id::create("item");
            item.rng        = rng.spawn();
            item.tgt_addr7  = tgt_addr7;
            item.tgt_addr10 = tgt_addr10;
            item.p_addr10   = p_addr10;
            item.p_bad_addr = p_bad_addr;
            item.p_bad_ptr  = p_bad_ptr;
            item.nregs      = nregs;
            item.max_wr     = max_wr;
            item.max_rd     = max_rd;
            item.w_kind     = w_kind;
            `odve_rand(item)
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
