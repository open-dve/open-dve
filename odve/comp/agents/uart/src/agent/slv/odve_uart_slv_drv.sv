// Slave driver: a peer UART device on the link, in place of the RTL. It
// receives on txd (odve_uart_phy::recv, 16x-style, nominal cfg.bit_clks),
// keeps every good character in a receive FIFO of cfg.fifo_depth entries
// and answers on s_rxd (top routes it onto rxd). Characters with a parity
// or framing error and breaks are dropped (n_err), a good character that
// finds the FIFO full is lost (n_oe, overrun). With cfg.flow_ctrl it drives
// s_cts_n high (not ready) once the FIFO holds fifo_depth-1 characters
// (auto-RTS) and waits for rts_n low before each character it sends
// (auto-CTS). Two modes (cfg.slv_mode):
//
//   ODVE_UART_SLV_MEM  autonomous: the answer is the received character
//                      complemented (~data, within the data bits) - the
//                      same transformation as the RTL echo device.
//   ODVE_UART_SLV_SEQ  reactive: each good character is published on
//                      req_port (the slave sequencer's req_fifo) and the
//                      answer comes back as an item from the responding
//                      sequence (seq/odve_uart_slv_echo_seq.sv, or your own;
//                      kind NONE sends nothing).
class odve_uart_slv_drv extends uvm_driver #(odve_uart_item);
    `uvm_component_utils(odve_uart_slv_drv)

    virtual odve_uart_if vif;
    odve_uart_cfg        cfg;
    uvm_analysis_port #(odve_uart_item) req_port;

    bit [7:0]    fifo[$];        // MEM mode
    int unsigned pending = 0;    // accepted characters not yet answered (the FIFO level)
    int unsigned n_rx = 0, n_err = 0, n_oe = 0, n_tx = 0;

    function new(string name = "odve_uart_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
    endfunction

    function void update_rts();
        vif.s_cts_n <= cfg.flow_ctrl && (pending >= cfg.fifo_depth - 1);
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.s_rxd   <= 1'b1;
        vif.s_cts_n <= 1'b0;
        wait (vif.rst_n === 1'b1);
        fork
            rx_loop();
            tx_loop();
        join
    endtask

    task rx_loop();
        odve_uart_item tr;
        time           t_start;
        int unsigned   clks;
        forever begin
            odve_uart_phy::recv(vif, ODVE_UART_TX, cfg, tr, t_start);
            if (tr.kind == ODVE_UART_GLITCH) continue;
            if (tr.brk) odve_uart_phy::wait_mark(vif, ODVE_UART_TX, clks);
            n_rx++;
            if (tr.pe || tr.fe || tr.brk) begin
                n_err++;
                `uvm_info(get_name(), $sformatf("dropped (error): %s", tr.convert2string()), UVM_MEDIUM)
                continue;
            end
            if (pending >= cfg.fifo_depth) begin
                n_oe++;
                `uvm_info(get_name(), $sformatf("overrun, lost: %s", tr.convert2string()), UVM_MEDIUM)
                continue;
            end
            pending++;
            update_rts();
            if (cfg.slv_mode == ODVE_UART_SLV_MEM) fifo.push_back(tr.data);
            else                                    req_port.write(tr);
        end
    endtask

    task tx_loop();
        odve_uart_item rsp;
        forever begin
            if (cfg.slv_mode == ODVE_UART_SLV_MEM) begin
                while (fifo.size() == 0) @(posedge vif.clk);
                rsp = odve_uart_item::type_id::create("rsp");
                rsp.data = ~fifo.pop_front() & odve_uart_mask(cfg.data_bits);
            end else begin
                seq_item_port.get_next_item(rsp);
            end
            if (rsp.kind == ODVE_UART_DATA) begin
                // start on a clock edge, after the auto-CTS check
                @(posedge vif.clk);
                if (cfg.flow_ctrl) while (vif.rts_n !== 1'b0) @(posedge vif.clk);
                pending--;
                update_rts();
                odve_uart_phy::send(vif, 1, cfg, rsp, cfg.tx_bit());
                n_tx++;
            end else begin
                pending--;
                update_rts();
            end
            if (cfg.slv_mode == ODVE_UART_SLV_SEQ) seq_item_port.item_done();
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("received %0d (%0d with errors dropped, %0d overrun), sent %0d", n_rx, n_err, n_oe, n_tx), UVM_LOW)
    endfunction
endclass
