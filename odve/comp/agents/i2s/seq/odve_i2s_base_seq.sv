// Base of the agent's sequences: n frames in the bus format of the agent's
// cfg (p_sequencer.cfg), values from `odve_rand on an odve_rand stream
// spawned per item. w_val weighs the sample kinds (odve_i2s_val_e: random,
// zero, +full scale, -full scale, +/-1), gap_max > 0 puts 0..gap_max idle
// frames before each frame (0 = back-to-back).
class odve_i2s_base_seq extends uvm_sequence #(odve_i2s_item);
    `uvm_object_utils(odve_i2s_base_seq)
    `uvm_declare_p_sequencer(odve_i2s_sqr)

    int unsigned n       = 16;
    int unsigned gap_max = 0;
    int unsigned w_val[];
    odve_rand    rng;

    function new(string name = "odve_i2s_base_seq");
        super.new(name);
        w_val = '{60, 10, 10, 10, 10};
    endfunction

    virtual task body();
        odve_i2s_item item;
        odve_i2s_cfg  cfg = p_sequencer.cfg;
        rng = new(get_full_name());
        for (int unsigned k = 0; k < n; k++) begin
            item = odve_i2s_item::type_id::create($sformatf("frame%0d", k));
            item.fmt      = cfg.fmt;
            item.word_len = cfg.word_len;
            item.slot_len = cfg.slot_len;
            item.n_slots  = cfg.n_slots;
            item.mono     = cfg.mono;
            item.w_val    = w_val;
            item.gap_max  = gap_max;
            item.rng      = rng.spawn(item.get_name());
            `odve_rand(item)
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
