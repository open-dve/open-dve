// The bits of one segment of a transfer: from a START or repeated START to
// the next Sr or STOP, one entry per SCL rising edge.
class odve_i3c_seg;
    bit is_sr;           // began with a repeated START
    bit bits[$];         // SDA at each rising edge
    bit cbits[$];        // what the controller drove (1 = released / high)
    bit hi[$];           // somebody drove SDA high (push-pull) at that edge

    function bit [7:0] byte_at(int unsigned k);
        bit [7:0] v;
        for (int i = 0; i < 8; i++) v[7 - i] = bits[k + i];
        return v;
    endfunction
    function bit [7:0] cbyte_at(int unsigned k);
        bit [7:0] v;
        for (int i = 0; i < 8; i++) v[7 - i] = cbits[k + i];
        return v;
    endfunction
endclass

// Passive I3C SDR observer. Samples SCL/SDA at every negedge of clk, finds
// START / repeated START / STOP (SDA edges while SCL is high), collects the
// bits of each segment and, at STOP, decodes the whole transfer into items:
// private write/read, broadcast/direct CCC, ENTDAA (every round), IBI and
// Hot-Join (a target won the header after a START: the address on the bus is
// not the one the controller drove). One item per transfer, published on
// item_collected_port and sampled into odve_i3c_cg.
//
// Protocol checks (UVM_ERROR):
//   - SDA contention: a push-pull high against a low from another driver
//   - a push-pull high in an open-drain phase (header + ACK after START, the
//     ENTDAA ID/address/ACK bits)
//   - SCL low or high for less than 2 clks inside a transfer
//   - write T-bit (odd parity) wrong (unless cfg.perr_is_error == 0: then
//     only counted, item.n_perr / item.perr_idx)
//   - ENTDAA address parity wrong, or a target ACKing an address with bad
//     parity
//   - a transfer ending inside a byte, or a read continuing after T=0
class odve_i3c_mon extends uvm_monitor;
    `uvm_component_utils(odve_i3c_mon)

    uvm_analysis_port #(odve_i3c_item) item_collected_port;
    virtual odve_i3c_if vif;
    odve_i3c_cfg        cfg;

    int unsigned n_seen, n_perr_seen, n_contention;

    // Functional coverage: the covergroup is declared in odve_i3c_agent_pkg
    // (package scope, `ifdef ODVE_COV_NATIVE); with FCOV=1 the build
    // generates odve_cov_pkg::odve_cov_odve_i3c_cg from it.
    `odve_cov_create(odve_i3c_cg)

    function new(string name = "odve_i3c_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void perr_report(string what);
        n_perr_seen++;
        if (cfg == null || cfg.perr_is_error) `uvm_error(get_name(), what)
        else `uvm_info(get_name(), {what, " (expected: perr_is_error = 0)"}, UVM_MEDIUM)
    endfunction

    // data bytes + T (odd parity) written by the controller, from bit k
    function void wr_stream(odve_i3c_seg s, int unsigned k, odve_i3c_item it);
        int unsigned idx = 0;
        it.perr_idx = -1;
        while (s.bits.size() >= k + 9) begin
            bit [7:0] v = s.byte_at(k);
            if (s.bits[k + 8] != i3c_par8(v)) begin
                it.n_perr++;
                if (it.perr_idx < 0) it.perr_idx = idx;
                perr_report($sformatf("write byte %0d (0x%02h) to 0x%02h: T-bit %0b, odd parity needs %0b",
                                      idx, v, it.addr, s.bits[k + 8], i3c_par8(v)));
            end
            it.data.push_back(v);
            k += 9;
            idx++;
        end
        if (s.bits.size() > k + 1)
            `uvm_error(get_name(), $sformatf("%s: transfer ended inside a byte (%0d stray bits)", it.kind.name(), s.bits.size() - k - 1))
    endfunction

    // data bytes + T (end of data) sent by a target, from bit k
    function void rd_stream(odve_i3c_seg s, int unsigned k, odve_i3c_item it);
        it.t_end = 0;
        while (s.bits.size() >= k + 9) begin
            it.data.push_back(s.byte_at(k));
            k += 9;
            if (!s.bits[k - 1]) begin it.t_end = 1; break; end
        end
        if (it.t_end && s.bits.size() > k + 1)
            `uvm_error(get_name(), $sformatf("%s from 0x%02h: %0d bit(s) after the target ended the read (T=0)", it.kind.name(), it.addr, s.bits.size() - k - 1))
        if (!it.t_end && s.bits.size() != k)
            `uvm_error(get_name(), $sformatf("%s from 0x%02h: read ended inside a byte (%0d stray bits)", it.kind.name(), it.addr, s.bits.size() - k))
    endfunction

    function void check_od(odve_i3c_seg s, int unsigned from, int unsigned to, string what);
        for (int unsigned k = from; k <= to && k < s.hi.size(); k++)
            if (s.hi[k]) begin
                `uvm_error(get_name(), $sformatf("push-pull high on SDA in the open-drain %s (bit %0d)", what, k))
                return;
            end
    endfunction

    function void emit(odve_i3c_item it);
        int ccc_v = (it.kind inside {I3C_CCC_BC, I3C_CCC_DW, I3C_CCC_DR, I3C_ENTDAA}) ? int'(it.ccc) : 256;
        int len_v = (it.kind == I3C_ENTDAA) ? it.daa_id.size() : it.data.size();
        bit rd    = it.kind inside {I3C_PRIV_RD, I3C_CCC_DR};
        n_seen++;
        `uvm_info(get_name(), it.convert2string(), UVM_HIGH)
        `odve_cov_sample(odve_i3c_cg, int'(it.kind), it.ack, ccc_v, len_v, rd, it.t_end, int'(it.n_perr))
        item_collected_port.write(it);
    endfunction

    function void decode_priv(odve_i3c_seg s, bit bc_7e);
        odve_i3c_item it = odve_i3c_item::type_id::create("tr");
        bit [7:0] h = s.byte_at(0);
        it.addr  = h[7:1];
        it.rnw   = h[0];
        it.kind  = h[0] ? I3C_PRIV_RD : I3C_PRIV_WR;
        it.ack   = (s.bits.size() > 8) && !s.bits[8];
        it.bc_7e = bc_7e;
        if (it.ack) begin
            if (it.rnw) rd_stream(s, 9, it);
            else        wr_stream(s, 9, it);
        end
        emit(it);
    endfunction

    // one transfer controlled by the controller, from segment i; returns the next segment
    function int unsigned decode_ctrl(ref odve_i3c_seg segs[$], input int unsigned i);
        odve_i3c_seg s = segs[i];
        bit [7:0] h;
        bit       ack;
        if (s.is_sr && s.bits.size() <= 1) return i + 1;   // Sr straight into P (e.g. after a read abort)
        if (s.bits.size() < 9) begin
            `uvm_error(get_name(), $sformatf("segment of %0d bit(s): no complete address header + ACK", s.bits.size()))
            return i + 1;
        end
        if (!s.is_sr) check_od(s, 0, 8, "address header / ACK after START");
        h   = s.byte_at(0);
        ack = !s.bits[8];
        if (h != {I3C_BCAST, 1'b0}) begin
            decode_priv(s, 0);
            return i + 1;
        end
        if (!ack) `uvm_warning(get_name(), "7'h7E/W not acknowledged: no target on the bus")
        if (s.bits.size() < 18) begin
            // 7E/W with no CCC: the private transfer(s) follow after Sr
            if (i + 1 < segs.size()) decode_priv(segs[i + 1], 1);
            return i + 2;
        end
        begin
            bit [7:0] c = s.byte_at(9);
            odve_i3c_item it = odve_i3c_item::type_id::create("tr");
            int unsigned j = i + 1;
            if (s.bits[17] != i3c_par8(c))
                perr_report($sformatf("CCC 0x%02h: T-bit %0b, odd parity needs %0b", c, s.bits[17], i3c_par8(c)));
            it.ccc = c;
            it.addr = I3C_BCAST;
            if (c == I3C_CCC_ENTDAA) begin
                it.kind = I3C_ENTDAA;
                it.ack  = ack;
                while (j < segs.size()) begin
                    odve_i3c_seg r = segs[j];
                    bit [7:0] rh;
                    if (r.bits.size() < 9) break;
                    rh = r.byte_at(0);
                    if (rh != {I3C_BCAST, 1'b1}) break;
                    j++;
                    if (r.bits[8]) continue;                  // nobody left without an address
                    if (r.bits.size() < 82) begin
                        `uvm_error(get_name(), $sformatf("ENTDAA round of %0d bits (82 expected)", r.bits.size()))
                        continue;
                    end
                    check_od(r, 8, 81, "ENTDAA ID / address / ACK");
                    begin
                        bit [63:0] id;
                        bit [6:0]  da;
                        bit        par_ok;
                        for (int b = 0; b < 64; b++) id[63 - b] = r.bits[9 + b];
                        for (int b = 0; b < 7; b++)  da[6 - b]  = r.bits[73 + b];
                        par_ok = (r.bits[80] == ~^da);
                        if (!par_ok) perr_report($sformatf("ENTDAA address 0x%02h: parity bit %0b, odd parity needs %0b", da, r.bits[80], ~^da));
                        if (!par_ok && !r.bits[81]) `uvm_error(get_name(), $sformatf("ENTDAA: a target ACKed address 0x%02h with a wrong parity bit", da))
                        it.daa_id.push_back(id);
                        it.daa_da.push_back(da);
                        it.daa_par_ok.push_back(par_ok);
                        it.daa_ack.push_back(!r.bits[81]);
                    end
                end
                emit(it);
                return j;
            end
            if (!c[7]) begin
                it.kind = I3C_CCC_BC;
                it.ack  = ack;
                wr_stream(s, 18, it);
                emit(it);
                return j;
            end
            // direct CCC: one Sr <addr>/RnW segment per target, until P or Sr 7E/W
            if (j >= segs.size()) `uvm_error(get_name(), $sformatf("direct CCC 0x%02h with no target segment", c))
            while (j < segs.size()) begin
                odve_i3c_seg r = segs[j];
                odve_i3c_item d;
                bit [7:0] rh;
                if (r.bits.size() < 9) break;
                rh = r.byte_at(0);
                if (rh == {I3C_BCAST, 1'b0}) break;
                d = odve_i3c_item::type_id::create("tr");
                d.ccc  = c;
                d.addr = rh[7:1];
                d.rnw  = rh[0];
                d.kind = rh[0] ? I3C_CCC_DR : I3C_CCC_DW;
                d.ack  = !r.bits[8];
                if (d.ack) begin
                    if (d.rnw) rd_stream(r, 9, d);
                    else       wr_stream(r, 9, d);
                end
                emit(d);
                j++;
            end
            return j;
        end
    endfunction

    function void decode(ref odve_i3c_seg segs[$]);
        int unsigned i = 0;
        if (segs.size() == 0) return;
        // after a START, a header the controller did not drive is a target's request
        if (!segs[0].is_sr && segs[0].bits.size() >= 9 && segs[0].byte_at(0) != segs[0].cbyte_at(0)) begin
            odve_i3c_seg  s  = segs[0];
            odve_i3c_item it = odve_i3c_item::type_id::create("tr");
            bit [7:0]     h  = s.byte_at(0);
            check_od(s, 0, 8, "arbitrated header / ACK");
            it.addr = h[7:1];
            it.rnw  = h[0];
            it.kind = (h[7:1] == I3C_HJ_ADDR && !h[0]) ? I3C_HOTJOIN : I3C_IBI;
            it.ack  = !s.bits[8];
            if (it.kind == I3C_IBI && it.ack && s.bits.size() > 10) rd_stream(s, 9, it);   // else: no payload (BCR[2] = 0)
            emit(it);
            i = 1;
        end
        while (i < segs.size()) i = decode_ctrl(segs, i);
    endfunction

    virtual task run_phase(uvm_phase phase);
        odve_i3c_seg segs[$];
        odve_i3c_seg cur;
        bit          p_scl = 1, p_sda = 1, in_frame = 0;
        int unsigned lo_cnt = 0, hi_cnt = 0;
        forever begin
            bit scl, sda;
            @(negedge vif.clk);
            if (vif.rst_n !== 1'b1) begin
                p_scl = 1; p_sda = 1; in_frame = 0; segs.delete(); cur = null;
                continue;
            end
            scl = vif.scl;
            sda = vif.sda;
            if (vif.contention === 1'b1) begin
                n_contention++;
                `uvm_error(get_name(), $sformatf("SDA contention: push-pull high against a low (oe m/t/d = %0b%0b%0b)",
                                                 vif.m_sda_oe, vif.t_sda_oe, vif.d_sda_oe))
            end
            if (scl && p_scl && p_sda && !sda) begin                   // START / Sr
                if (cur != null) segs.push_back(cur);
                cur = new();
                cur.is_sr = in_frame;
                in_frame = 1;
            end else if (scl && p_scl && !p_sda && sda) begin          // STOP
                if (cur != null) segs.push_back(cur);
                if (in_frame) decode(segs);
                segs.delete();
                cur = null;
                in_frame = 0;
            end else if (scl && !p_scl && cur != null) begin           // rising edge: a bit
                cur.bits.push_back(sda);
                cur.cbits.push_back(!(vif.m_sda_oe && !vif.m_sda_o));
                cur.hi.push_back(vif.drive_hi);
            end
            // SCL timing inside a transfer
            if (in_frame) begin
                if (scl && !p_scl && lo_cnt < 2) `uvm_error(get_name(), $sformatf("SCL low for %0d clk(s), 2 at least", lo_cnt))
                if (!scl && p_scl && hi_cnt < 2) `uvm_error(get_name(), $sformatf("SCL high for %0d clk(s), 2 at least", hi_cnt))
            end
            if (scl) begin hi_cnt = (p_scl ? hi_cnt : 0) + 1; end
            else     begin lo_cnt = (!p_scl ? lo_cnt : 0) + 1; end
            p_scl = scl;
            p_sda = sda;
        end
    endtask
endclass
