// Two stream checks, in order, frame by frame:
//   A  what the transmitter agent's driver sent (sent_imp) against what the
//      port A monitor rebuilt from the pins (a_imp): agent TX vs monitor /
//      receiver agent
//   B  the DUT reference model applied to the port A frames against what
//      the port B monitor rebuilt (b_imp): out slot k = -(in slot k^1),
//      word_len-bit two's complement, -full scale saturating to +full scale
// All-zero frames are idle frames (sent while no data is pending, and what
// the DUT sends while its buffer is empty): they never mismatch, and an
// expected all-zero frame may be skipped. Every non-zero expected frame
// must arrive, in order, before the end of the test. With check = 0
// (negative tests) nothing is reported and the stream resynchronises on
// the next matching frame, so the test can count what got through.
`uvm_analysis_imp_decl(_sent)
`uvm_analysis_imp_decl(_a)
`uvm_analysis_imp_decl(_b)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_sent #(odve_i2s_item, scb) sent_imp;
    uvm_analysis_imp_a    #(odve_i2s_item, scb) a_imp;
    uvm_analysis_imp_b    #(odve_i2s_item, scb) b_imp;

    bit           check   = 1;    // 0: count only (negative tests)
    bit           has_dut = 1;
    odve_i2s_item q_a[$];         // sent, waiting for port A
    odve_i2s_item q_b[$];         // predicted, waiting for port B
    int unsigned  n_sent = 0, n_a = 0, n_b = 0, match_a = 0, match_b = 0, idle_a = 0, idle_b = 0;

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sent_imp = new("sent_imp", this);
        a_imp    = new("a_imp", this);
        b_imp    = new("b_imp", this);
    endfunction

    static function bit [31:0] negsat(bit [31:0] v, int unsigned w);
        bit [31:0] m   = (w >= 32) ? 32'hFFFF_FFFF : ((32'h1 << w) - 1);
        bit [31:0] min = (m >> 1) + 1;
        v &= m;
        if (v == min) return m >> 1;
        return (~v + 1) & m;
    endfunction

    function odve_i2s_item predict(odve_i2s_item in);
        odve_i2s_item p = odve_i2s_item::type_id::create("pred");
        p.fmt = in.fmt; p.word_len = in.word_len; p.slot_len = in.slot_len; p.n_slots = in.n_slots;
        for (int unsigned k = 0; k < in.n_slots; k++) p.data[k] = negsat(in.data[k ^ 1], in.word_len);
        return p;
    endfunction

    // in-order match with idle (all-zero) frames skipped; 1 = matched a frame
    function bit match(ref odve_i2s_item q[$], input odve_i2s_item tr, input string port, ref int unsigned idle);
        odve_i2s_item e;
        if (tr.is_zero()) begin
            if (q.size() > 0 && q[0].is_zero()) void'(q.pop_front());
            idle++;
            return 0;
        end
        while (q.size() > 0 && q[0].is_zero()) void'(q.pop_front());
        if (q.size() == 0) begin
            if (check) `uvm_error(get_name(), $sformatf("port %s: unexpected frame %s", port, tr.convert2string()))
            return 0;
        end
        if (!check) begin
            // negative tests: a frame broken by an injected error is lost
            // or garbled; resynchronise on the next frame that matches
            int idx[$] = q.find_first_index(x) with (x.same_data(tr));
            if (idx.size() == 0) return 0;
            repeat (idx[0]) void'(q.pop_front());
        end
        e = q.pop_front();
        if (!tr.same_data(e)) begin
            `uvm_error(get_name(), $sformatf("port %s: frame %s, expected %s", port, tr.convert2string(), e.convert2string()))
            return 0;
        end
        `uvm_info(get_name(), $sformatf("port %s: frame %s ok", port, tr.convert2string()), UVM_HIGH)
        return 1;
    endfunction

    function void write_sent(odve_i2s_item tr);
        n_sent++;
        q_a.push_back(tr);
    endfunction

    function void write_a(odve_i2s_item tr);
        n_a++;
        if (match(q_a, tr, "A", idle_a)) match_a++;
        if (has_dut) q_b.push_back(predict(tr));
    endfunction

    function void write_b(odve_i2s_item tr);
        n_b++;
        if (match(q_b, tr, "B", idle_b)) match_b++;
    endfunction

    function int unsigned pending(ref odve_i2s_item q[$]);
        int unsigned n = 0;
        foreach (q[i]) if (!q[i].is_zero()) n++;
        return n;
    endfunction

    virtual function void check_phase(uvm_phase phase);
        if (!check) return;
        if (pending(q_a) != 0)
            `uvm_error(get_name(), $sformatf("port A: %0d sent frame(s) never seen on the bus", pending(q_a)))
        if (pending(q_b) != 0)
            `uvm_error(get_name(), $sformatf("port B: %0d expected frame(s) never sent by the DUT", pending(q_b)))
        if (match_a == 0)
            `uvm_error(get_name(), "port A: no frame checked")
        if (has_dut && match_b == 0)
            `uvm_error(get_name(), "port B: no frame checked")
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("port A: %0d sent, %0d observed, %0d matched, %0d idle; port B: %0d observed, %0d matched, %0d idle%s",
                  n_sent, n_a, match_a, idle_a, n_b, match_b, idle_b, check ? "" : " (checks off)"), UVM_LOW)
    endfunction
endclass : scb
