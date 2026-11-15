// Reference model of the echo peer (the RTL device or the slave agent):
// every character the master sends on txd without an error must come back
// on rxd, in order, complemented within the data bits; a character with a
// parity or framing error, or a break, is not echoed; nothing arrives on rxd
// that was not expected, and nothing on rxd carries an error.
//
// With the RTL device (check_status) its status pins are checked too: each
// errored character must be reported once with the same flags (pe / fe / bi
// as the monitor classified it), and an overrun (oe) is only allowed when
// the test expects it (expect_oe) - the lost character is then the txd
// character received at the same time, and is no longer expected back.
// Status reports and monitor items are paired by time (the stop-bit sample
// of the character, within `tol`), whichever arrives first.
`uvm_analysis_imp_decl(_uart)

class scb_rec;
    bit [7:0] data;      // TX: expected echo
    time      t;
    bit       pe, fe, bi, oe;
    bit       dropped;
endclass

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_uart #(odve_uart_item, scb) uart_imp;
    odve_uart_cfg      cfg;
    virtual uart_tb_if vtb;
    bit                check_status = 0;
    bit                expect_oe    = 0;

    scb_rec      exp_q[$];      // good txd characters waiting for their echo
    scb_rec      err_q[$];      // errored txd characters waiting for the DUT's report
    scb_rec      st_q[$];       // DUT reports not paired yet
    time         tol = 0;

    int unsigned n_tx = 0, n_tx_ok = 0, n_pe = 0, n_fe = 0, n_brk = 0;
    int unsigned n_rx = 0, n_echo = 0, n_oe = 0, n_st = 0;

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uart_imp = new("uart_imp", this);
    endfunction

    // characters still owed by the peer
    function int unsigned pending();
        int unsigned n = 0;
        foreach (exp_q[i]) if (!exp_q[i].dropped) n++;
        return n;
    endfunction

    function void write_uart(odve_uart_item tr);
        scb_rec r = new();
        r.t = tr.t_end;
        if (tr.dir == ODVE_UART_TX) begin
            n_tx++;
            if (tr.pe)  n_pe++;
            if (tr.fe)  n_fe++;
            if (tr.brk) n_brk++;
            if (tr.pe || tr.fe || tr.brk) begin
                r.pe = tr.pe;
                r.fe = tr.fe;
                r.bi = tr.brk;
                if (check_status) err_q.push_back(r);
            end else begin
                n_tx_ok++;
                r.data = ~tr.data & odve_uart_mask(tr.data_bits);
                exp_q.push_back(r);
            end
            pair_status();
        end else begin
            n_rx++;
            if (tr.pe || tr.fe || tr.brk)
                `uvm_error(get_name(), $sformatf("errored character from the peer: %s", tr.convert2string()))
            while (exp_q.size() > 0 && exp_q[0].dropped) void'(exp_q.pop_front());
            if (exp_q.size() == 0) begin
                `uvm_error(get_name(), $sformatf("unexpected character from the peer: %s", tr.convert2string()))
            end else begin
                scb_rec e = exp_q.pop_front();
                if (tr.data !== e.data)
                    `uvm_error(get_name(), $sformatf("echo 0x%02h, expected 0x%02h (~ of 0x%02h): %s", tr.data, e.data,
                                                     ~e.data & odve_uart_mask(tr.data_bits), tr.convert2string()))
                else
                    n_echo++;
            end
        end
    endfunction

    function bit near(time a, time b);
        return (a > b) ? (a - b <= tol) : (b - a <= tol);
    endfunction

    // Pair DUT status reports with the txd characters they belong to.
    function void pair_status();
        int i = 0;
        while (i < st_q.size()) begin
            scb_rec s = st_q[i];
            bit done = 0;
            if (s.oe) begin
                // the lost character: the newest good one received at that time
                for (int j = exp_q.size() - 1; j >= 0 && !done; j--)
                    if (!exp_q[j].dropped && near(exp_q[j].t, s.t)) begin
                        exp_q[j].dropped = 1;
                        done = 1;
                    end
            end else begin
                for (int j = 0; j < err_q.size() && !done; j++)
                    if (near(err_q[j].t, s.t)) begin
                        if (err_q[j].pe != s.pe || err_q[j].fe != s.fe || err_q[j].bi != s.bi)
                            `uvm_error(get_name(), $sformatf("DUT status pe=%0b fe=%0b bi=%0b at %0t, monitor saw pe=%0b fe=%0b brk=%0b",
                                                             s.pe, s.fe, s.bi, s.t, err_q[j].pe, err_q[j].fe, err_q[j].bi))
                        err_q.delete(j);
                        done = 1;
                    end
                // the monitor saw a good character at that time: the DUT is wrong
                for (int j = 0; j < exp_q.size() && !done; j++)
                    if (!exp_q[j].dropped && near(exp_q[j].t, s.t)) begin
                        `uvm_error(get_name(), $sformatf("DUT status pe=%0b fe=%0b bi=%0b at %0t for a character the monitor received without error (echo 0x%02h expected)",
                                                         s.pe, s.fe, s.bi, s.t, exp_q[j].data))
                        exp_q[j].dropped = 1;
                        done = 1;
                    end
            end
            if (done) st_q.delete(i);
            else      i++;
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        time t0, clk_per;
        if (!check_status) return;
        wait (vtb.rst_n === 1'b1);
        @(posedge vtb.clk);
        t0 = $time;
        @(posedge vtb.clk);
        clk_per = $time - t0;
        forever begin
            @(posedge vtb.clk);
            // four bit times either side of the stop-bit sample: far more
            // than the receivers differ by, far less than a frame
            tol = 4 * cfg.bit_clks * clk_per;
            if (vtb.st_valid === 1'b1) begin
                scb_rec s = new();
                s.t  = $time;
                s.oe = vtb.st_oe;
                s.pe = vtb.st_pe;
                s.fe = vtb.st_fe;
                s.bi = vtb.st_bi;
                n_st++;
                if (s.oe) begin
                    n_oe++;
                    if (!expect_oe)
                        `uvm_error(get_name(), $sformatf("DUT reported an overrun at %0t", s.t))
                end
                st_q.push_back(s);
                pair_status();
            end
        end
    endtask

    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (pending() != 0)
            `uvm_error(get_name(), $sformatf("%0d character(s) sent on txd never came back, first expected 0x%02h", pending(), exp_q[0].data))
        if (err_q.size() != 0)
            `uvm_error(get_name(), $sformatf("%0d errored character(s) not reported by the DUT, first at %0t", err_q.size(), err_q[0].t))
        if (st_q.size() != 0)
            `uvm_error(get_name(), $sformatf("%0d DUT status report(s) with no matching character, first at %0t", st_q.size(), st_q[0].t))
        if (n_tx == 0)
            `uvm_error(get_name(), "no characters observed on txd")
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("txd: %0d characters (%0d good, %0d parity err, %0d framing err, %0d breaks); rxd: %0d characters, %0d echoes checked; DUT status reports %0d (%0d overrun)",
                                        n_tx, n_tx_ok, n_pe, n_fe, n_brk, n_rx, n_echo, n_st, n_oe), UVM_LOW)
    endfunction
endclass : scb
