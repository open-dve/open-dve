// The reactive slave's behaviour, as a sequence (cfg.slv_mode ==
// ODVE_UART_SLV_SEQ): waits for each character the slave driver drops into
// the sequencer's req_fifo and answers with its complement (~data within the
// data bits), the same echo as the RTL device. Never ends: start it in a fork
// from the test and do not hold an objection for it.
class odve_uart_slv_echo_seq extends uvm_sequence #(odve_uart_item);
    `uvm_object_utils(odve_uart_slv_echo_seq)
    `uvm_declare_p_sequencer(odve_uart_slv_sqr)

    int unsigned n_resp = 0;

    function new(string name = "odve_uart_slv_echo_seq");
        super.new(name);
    endfunction

    virtual task body();
        odve_uart_item req, rsp;
        forever begin
            p_sequencer.req_fifo.get(req);
            rsp = odve_uart_item::type_id::create("rsp");
            rsp.kind = ODVE_UART_DATA;
            rsp.data = ~req.data & odve_uart_mask(p_sequencer.cfg.data_bits);
            n_resp++;
            start_item(rsp);
            finish_item(rsp);
        end
    endtask
endclass
