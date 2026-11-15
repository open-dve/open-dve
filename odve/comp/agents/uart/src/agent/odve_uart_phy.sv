// Bit-level UART line access shared by the drivers and the monitor. All
// timing is in clk cycles: lines are driven with non-blocking assignments at
// posedge and sampled at posedge (the value before that edge's updates), so
// a receiver here and the RTL see the same thing.
class odve_uart_phy;

    // the value of one line: TX = txd (master -> peer), RX = rxd (peer -> master)
    static function logic line(virtual odve_uart_if vif, odve_uart_dir_e dir);
        return (dir == ODVE_UART_TX) ? vif.txd : vif.rxd;
    endfunction

    static task drive(virtual odve_uart_if vif, bit slave, logic v);
        if (slave) vif.s_rxd <= v;
        else       vif.txd   <= v;
    endtask

    // Transmit one character: start, data LSB first, parity, stop bits, at
    // bc clocks per bit. Injections: it.bad_parity flips the parity bit,
    // it.bad_stop sends the first stop bit as space. Leaves the line at mark.
    static task send(virtual odve_uart_if vif, bit slave, odve_uart_cfg cfg, odve_uart_item it, int unsigned bc);
        int unsigned sc = cfg.stop_clks(bc);
        drive(vif, slave, 1'b0);                                     // start
        repeat (bc) @(posedge vif.clk);
        for (int i = 0; i < int'(cfg.data_bits); i++) begin
            drive(vif, slave, it.data[i]);
            repeat (bc) @(posedge vif.clk);
        end
        if (cfg.parity != ODVE_UART_PAR_NONE) begin
            drive(vif, slave, odve_uart_parity(it.data, cfg.data_bits, cfg.parity) ^ it.bad_parity);
            repeat (bc) @(posedge vif.clk);
        end
        if (it.bad_stop) begin
            drive(vif, slave, 1'b0);
            repeat (bc) @(posedge vif.clk);
            sc = sc - bc;
        end
        drive(vif, slave, 1'b1);                                     // stop
        repeat (sc) @(posedge vif.clk);
    endtask

    // Receive one character on `dir` the way a 16x-oversampling receiver
    // does (16550): wait for mark, then for the falling edge of a start
    // bit; check the start bit again at its middle (still space, else it was
    // a glitch: kind = GLITCH, nothing else filled in); sample every further
    // bit at its middle, nominal bit period cfg.bit_clks counted from the
    // edge; only the first stop bit is checked. Classification as the RTL
    // (vrf/dut/dut.sv) does it:
    //   brk = start, data, parity and stop bit all space (pe = fe = 0)
    //   fe  = first stop bit space (and not a break)
    //   pe  = parity bit differs from what cfg.parity demands
    // Returns right after the stop-bit sample (t_end); the caller decides
    // what to do with the rest of the stop time or a held break.
    static task recv(virtual odve_uart_if vif, odve_uart_dir_e dir, odve_uart_cfg cfg, output odve_uart_item tr, output time t_start);
        int unsigned bc = cfg.bit_clks;
        bit [7:0] d = '0;
        bit p = 1'b0, s;
        tr = odve_uart_item::type_id::create("tr");
        tr.dir = dir;
        while (line(vif, dir) !== 1'b1) @(posedge vif.clk);          // mark
        while (line(vif, dir) !== 1'b0) @(posedge vif.clk);          // start edge
        t_start = $time;
        repeat (bc / 2) @(posedge vif.clk);
        if (line(vif, dir) !== 1'b0) begin                           // false start bit
            tr.kind = ODVE_UART_GLITCH;
            return;
        end
        tr.data_bits = cfg.data_bits;
        tr.parity    = cfg.parity;
        tr.stop      = cfg.stop;
        for (int i = 0; i < int'(cfg.data_bits); i++) begin
            repeat (bc) @(posedge vif.clk);
            d[i] = line(vif, dir);
        end
        if (cfg.parity != ODVE_UART_PAR_NONE) begin
            repeat (bc) @(posedge vif.clk);
            p = line(vif, dir);
        end
        repeat (bc) @(posedge vif.clk);
        s = line(vif, dir);
        tr.t_end = $time;
        tr.data  = d;
        tr.brk   = (s == 1'b0) && (d == 0) && (p == 1'b0);
        tr.kind  = tr.brk ? ODVE_UART_BREAK : ODVE_UART_DATA;
        tr.fe    = (s == 1'b0) && !tr.brk;
        tr.pe    = !tr.brk && (cfg.parity != ODVE_UART_PAR_NONE) && (p != odve_uart_parity(d, cfg.data_bits, cfg.parity));
    endtask

    // Wait until `dir` is back at mark; returns the clocks waited.
    static task wait_mark(virtual odve_uart_if vif, odve_uart_dir_e dir, output int unsigned clks);
        clks = 0;
        while (line(vif, dir) !== 1'b1) begin
            @(posedge vif.clk);
            clks++;
        end
    endtask
endclass
