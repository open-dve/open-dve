// Base of the host sequences: one operation item built from the fields
// below and sent to the master driver; the driver's answer (tdo,
// end_state) is copied back so the caller can read it after start().
class odve_jtag_base_seq extends uvm_sequence #(odve_jtag_item);
    `uvm_object_utils(odve_jtag_base_seq)

    odve_jtag_kind_e  kind         = JTAG_IDLE;
    int unsigned      len          = 0;
    odve_jtag_vec_t   tdi          = '0;
    bit               use_trst     = 0;
    int unsigned      pause_at     = 0;
    int unsigned      pause_cycles = 1;
    int unsigned      idle         = 0;
    odve_jtag_state_e target       = RTI;
    // results
    odve_jtag_vec_t   tdo;
    odve_jtag_state_e end_state;

    function new(string name = "odve_jtag_base_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_jtag_item item = odve_jtag_item::type_id::create("item");
        item.kind         = kind;
        item.len          = len;
        item.tdi          = tdi;
        item.use_trst     = use_trst;
        item.pause_at     = pause_at;
        item.pause_cycles = pause_cycles;
        item.idle         = idle;
        item.target       = target;
        start_item(item);
        finish_item(item);
        tdo       = item.tdo;
        end_state = item.end_state;
    endtask
endclass
