// n random frames (odve_mdio_item::user_randomize, from this sequence's
// odve_rand stream): kinds by w_kind, addresses from addrs, miss_pct % to a
// PHY/port/MMD nobody answers, idle cycles 0..max_idle after each frame and,
// with long_pre_pct, preambles longer than 32.
class odve_mdio_rand_seq extends odve_mdio_base_seq;
    `uvm_object_utils(odve_mdio_rand_seq)

    int unsigned n            = 20;
    bit [4:0]    addrs[$]     = '{5'd1};
    int unsigned miss_pct     = 0;
    int unsigned max_idle     = 2;
    int unsigned long_pre_pct = 0;
    int unsigned w_kind[]     = '{2, 2, 2, 2, 2, 1};
    odve_rand    rng;

    function new(string name = "odve_mdio_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_mdio_item it;
        rng = new(get_full_name());
        q.delete();
        repeat (n) begin
            it = odve_mdio_item::type_id::create($sformatf("r%0d", q.size()));
            it.rng      = rng;
            it.addrs    = addrs;
            it.miss_pct = miss_pct;
            it.w_kind   = w_kind;
            `odve_rand(it)
            it.idle = rng.urange(max_idle);
            if (long_pre_pct != 0 && rng.chance(long_pre_pct)) it.pre_len = 32 + rng.urange(8, 1);
            q.push_back(it);
        end
        super.body();
    endtask
endclass
