// n random operations: resets (TMS or TRST_n), IR scans loading a known
// instruction (or an unassigned one, which must act as BYPASS) into every
// TAP of the chain, DR scans of random length and data, pauses, idle
// cycles, and now and then a detour to a random state. Values come from the
// odve_rand stream rng (spawned by the caller, or made from the sequence's
// name).
class odve_jtag_rand_seq extends uvm_sequence #(odve_jtag_item);
    `uvm_object_utils(odve_jtag_rand_seq)

    int unsigned n          = 40;
    int unsigned n_taps     = 1;     // TAPs in the chain, 4-bit IR each
    int unsigned max_dr_len = 80;
    odve_rand    rng;

    function new(string name = "odve_jtag_rand_seq");
        super.new(name);
    endfunction

    function bit [3:0] pick_instr();
        int unsigned k = rng.urand(0, 5);
        case (k)
            0: return ODVE_JTAG_EXTEST;
            1: return ODVE_JTAG_SAMPLE;
            2: return ODVE_JTAG_IDCODE;
            3: return ODVE_JTAG_USERDATA;
            4: return ODVE_JTAG_BYPASS;
            default: return 4'(rng.urand(3, 7));   // unassigned -> BYPASS
        endcase
    endfunction

    virtual task body();
        odve_jtag_item item;
        if (rng == null) rng = new(get_full_name());
        repeat (n) begin
            if (rng.chance(5)) begin
                item = odve_jtag_item::type_id::create("item");
                item.kind   = JTAG_GOTO;
                item.target = odve_jtag_state_e'(rng.urand(0, 15));
                start_item(item);
                finish_item(item);
            end
            item = odve_jtag_item::type_id::create("item");
            item.rng        = rng;
            item.ir_len     = 4 * n_taps;
            item.max_dr_len = max_dr_len;
            `odve_rand(item)
            if (item.kind == JTAG_IR && rng.chance(85)) begin
                item.tdi = '0;
                for (int unsigned t = 0; t < n_taps; t++) begin
                    bit [3:0] op = pick_instr();
                    item.tdi |= odve_jtag_vec_t'(op) << (4 * t);
                end
            end
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
