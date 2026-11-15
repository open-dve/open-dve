// n characters on the master sequencer, values from `odve_rand: data within
// the link's data bits, an idle gap with gap_pct % chance (up to max_idle
// bit times; gap_pct = 0: back to back), and with err_pct % chance an error
// event instead (weights err_w: bad parity, bad stop bit, break, glitch).
// rng: the sequence's stream, spawned by the test (or made from the
// sequence's full name); each item gets its own spawned stream.
class odve_uart_base_seq extends uvm_sequence #(odve_uart_item);
    `uvm_object_utils(odve_uart_base_seq)
    `uvm_declare_p_sequencer(odve_uart_sqr)

    int unsigned n        = 16;
    int unsigned gap_pct  = 30;
    int unsigned max_idle = 4;
    int unsigned err_pct  = 0;
    int unsigned err_w[];
    odve_rand    rng;

    function new(string name = "odve_uart_base_seq");
        super.new(name);
        err_w = '{1, 1, 1, 1};
    endfunction

    virtual function void prep(odve_uart_item item, int unsigned i);
        item.rng       = rng.spawn($sformatf("item%0d", i));
        item.data_bits = p_sequencer.cfg.data_bits;
        item.parity    = p_sequencer.cfg.parity;
        item.bit_clks  = p_sequencer.cfg.bit_clks;
        item.gap_pct   = gap_pct;
        item.max_idle  = max_idle;
        item.err_pct   = err_pct;
        item.err_w     = err_w;
    endfunction

    virtual task body();
        odve_uart_item item;
        if (rng == null) rng = new(get_full_name());
        for (int unsigned i = 0; i < n; i++) begin
            item = odve_uart_item::type_id::create("item");
            prep(item, i);
            `odve_rand(item)
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
