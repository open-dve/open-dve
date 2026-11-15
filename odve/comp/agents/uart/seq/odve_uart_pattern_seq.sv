// The characters in `pattern`, in order, each after idle_bits of mark (0 =
// back to back), masked to the link's data bits. Default pattern: all
// space, all mark, alternating bits both ways, one bit set at each end.
class odve_uart_pattern_seq extends uvm_sequence #(odve_uart_item);
    `uvm_object_utils(odve_uart_pattern_seq)
    `uvm_declare_p_sequencer(odve_uart_sqr)

    bit [7:0]    pattern[$];
    int unsigned idle_bits = 0;

    function new(string name = "odve_uart_pattern_seq");
        super.new(name);
        pattern = '{8'h00, 8'hFF, 8'h55, 8'hAA, 8'h01, 8'h80};
    endfunction

    virtual task body();
        odve_uart_item item;
        foreach (pattern[i]) begin
            item = odve_uart_item::type_id::create("item");
            item.kind      = ODVE_UART_DATA;
            item.data      = pattern[i] & odve_uart_mask(p_sequencer.cfg.data_bits);
            item.idle_bits = idle_bits;
            start_item(item);
            finish_item(item);
        end
    endtask
endclass
