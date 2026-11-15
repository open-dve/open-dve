// n random command sequences. Every value comes from the sequence's own
// odve_rand stream (handed to each item, drawn in user_randomize()); the
// knobs below select the kinds, targets, address range and parity-error
// injection. n_inj counts the items sent with an injected
// parity error.
class odve_spmi_base_seq extends uvm_sequence #(odve_spmi_item);
    `uvm_object_utils(odve_spmi_base_seq)

    int unsigned n         = 8;
    bit [10:0]   kind_mask = 11'h07F; // bit k enables odve_spmi_kind_e k
    bit [3:0]    sids[$];             // targets; empty = 4'h5
    int unsigned nregs     = 64;
    int unsigned oor_pct   = 0;
    int unsigned inj_pct   = 0;
    int unsigned n_inj     = 0;
    odve_rand    rng;

    function new(string name = "odve_spmi_base_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_spmi_item item;
        if (rng == null) rng = new(get_full_name());
        repeat (n) begin
            item = odve_spmi_item::type_id::create("item");
            item.rng       = rng;
            item.kind_mask = kind_mask;
            item.sids      = sids;
            if (sids.size() == 0) item.sids.push_back(4'h5);
            item.nregs     = nregs;
            item.oor_pct   = oor_pct;
            item.inj_pct   = inj_pct;
            `odve_rand(item)
            if (item.inj_par_frame >= 0) n_inj++;
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
