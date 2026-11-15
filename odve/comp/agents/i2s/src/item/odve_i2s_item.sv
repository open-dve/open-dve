// One I2S / TDM frame: n_slots samples (2 = left/right for the stereo
// formats), each word_len bits two's complement, right-aligned in data[].
// No `rand`/constraints: user_randomize() takes every value from the
// odve_rand stream `rng`, which the sequence spawns per item
// (comp/common/rand/README, rule 3).
class odve_i2s_item extends uvm_sequence_item;
    `uvm_object_utils(odve_i2s_item)

    // frame shape (copied from the agent cfg by the sequence / monitor)
    odve_i2s_fmt_e fmt      = ODVE_I2S_FMT_I2S;
    int unsigned   word_len = 16;
    int unsigned   slot_len = 32;
    int unsigned   n_slots  = 2;
    bit            mono     = 0;   // stereo formats: both channels carry the same sample

    bit [31:0]     data [ODVE_I2S_MAX_SLOTS];   // slot k, right-aligned word_len bits
    int unsigned   gap = 0;        // transmitter: idle (all-zero) frames sent before this one

    // user_randomize() knobs
    odve_rand      rng;
    int unsigned   w_val[];        // weights of odve_i2s_val_e, set in new()
    int unsigned   gap_max  = 0;

    function new(string name = "odve_i2s_item");
        super.new(name);
        foreach (data[i]) data[i] = '0;
        w_val = '{60, 10, 10, 10, 10};
    endfunction

    function bit [31:0] mask();
        return (word_len >= 32) ? 32'hFFFF_FFFF : ((32'h1 << word_len) - 1);
    endfunction

    // one value of the given kind, word_len bits
    function bit [31:0] value_of(odve_i2s_val_e k);
        bit [31:0] v;
        case (k)
            ODVE_I2S_VAL_ZERO:  v = '0;
            ODVE_I2S_VAL_MAX:   v = mask() >> 1;                    // 0111..1
            ODVE_I2S_VAL_MIN:   v = (mask() >> 1) + 1;              // 1000..0
            ODVE_I2S_VAL_SMALL: v = rng.chance(50) ? 32'h1 : mask(); // +1 / -1
            default:            v = rng.u32();
        endcase
        return v & mask();
    endfunction

    function void user_randomize();
        int unsigned k;
        if (rng == null) rng = new(get_name());
        for (int unsigned i = 0; i < ODVE_I2S_MAX_SLOTS; i++) begin
            if (i < n_slots) begin
                k = rng.weighted(w_val);
                data[i] = value_of(odve_i2s_val_e'(k));
            end else begin
                data[i] = '0;
            end
        end
        if (mono) data[1] = data[0];
        gap = (gap_max == 0) ? 0 : rng.urand(0, gap_max);
    endfunction

    function bit is_zero();
        for (int unsigned i = 0; i < n_slots; i++)
            if (data[i] != 0) return 0;
        return 1;
    endfunction

    function bit same_data(odve_i2s_item o);
        if (o.n_slots != n_slots) return 0;
        for (int unsigned i = 0; i < n_slots; i++)
            if (data[i] != o.data[i]) return 0;
        return 1;
    endfunction

    // classification of one sample, for coverage: 0 zero, 1 +full scale,
    // 2 -full scale, 3 other positive, 4 other negative
    function int unsigned val_class(int unsigned slot);
        bit [31:0] v = data[slot] & mask();
        if (v == 0)                 return 0;
        if (v == (mask() >> 1))     return 1;
        if (v == (mask() >> 1) + 1) return 2;
        if (v[word_len-1] == 1'b0)  return 3;
        return 4;
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("%s w%0d/s%0d", fmt.name(), word_len, slot_len);
        for (int unsigned i = 0; i < n_slots; i++) s = {s, $sformatf(" %0d:%0h", i, data[i])};
        return s;
    endfunction
endclass
