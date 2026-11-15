// n random private transfers (odve_i3c_item::user_randomize: write = register
// pointer + data, or read of 1..max_len bytes) spread over tgt_addrs.
class odve_i3c_priv_rand_seq extends odve_i3c_base_seq;
    `uvm_object_utils(odve_i3c_priv_rand_seq)

    int unsigned n       = 20;
    int unsigned max_len = 8;
    bit [6:0]    tgt_addrs[$];

    function new(string name = "odve_i3c_priv_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        rng_init();
        repeat (n) begin
            odve_i3c_item it = odve_i3c_item::type_id::create("it");
            it.rng       = rng.spawn("it");
            it.tgt_addrs = tgt_addrs;
            it.max_len   = max_len;
            `odve_rand(it)
            xfer(it);
        end
    endtask
endclass
