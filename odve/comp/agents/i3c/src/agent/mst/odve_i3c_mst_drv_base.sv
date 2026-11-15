// I3C SDR controller. Owns SCL (push-pull) and drives SDA through
// m_sda_oe/m_sda_o/m_sda_pp: open-drain for the address header after a
// START (where targets may arbitrate an IBI / Hot-Join), the ACK bits and the
// whole ENTDAA round; push-pull for write data, CCC codes, T-bits and the
// header after a repeated START.
//
// Timing, in clk cycles of the interface: SCL low cfg.t_low, high
// cfg.t_high. SDA is changed one clk after SCL falls (targets react on that
// same clk) and sampled one clk after SCL rises. Every decision is taken at
// a posedge on values sampled at the preceding negedge (tick()), so the
// driver never races the RTL.
//
// Item kinds: see odve_i3c_kind_e. Results go back in the same item (ack,
// read data, t_end, ENTDAA rounds). A target that wins the header after the
// driver's START (IBI or Hot-Join) is served first (ACK/NACK per cfg, IBI
// payload read when the target's BCR says so); after a NACK the driver goes
// on with a repeated START, after an ACK with STOP + START. With no item to
// run, the driver watches the idle bus for a target's START request.
class odve_i3c_mst_drv_base extends uvm_driver #(odve_i3c_item);
    `uvm_component_utils(odve_i3c_mst_drv_base)

    virtual odve_i3c_if vif;
    odve_i3c_cfg        cfg;

    bit          s_scl, s_sda;          // bus as sampled before the current posedge
    bit [7:0]    da_bcr [bit [6:0]];    // BCR of each dynamic address (ENTDAA, GETBCR)
    int unsigned n_ibi_ack, n_ibi_nack, n_hj_ack, n_hj_nack;
    uvm_analysis_port #(odve_i3c_item) evt_port;   // IBIs / Hot-Joins the driver served

    function new(string name = "odve_i3c_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        evt_port = new("evt_port", this);
    endfunction

    // ------------------------------------------------------------ pin level
    task tick();
        @(negedge vif.clk);
        s_scl = vif.scl;
        s_sda = vif.sda;
        @(posedge vif.clk);
    endtask

    function void sda_release();
        vif.m_sda_oe <= 1'b0;
        vif.m_sda_pp <= 1'b0;
    endfunction
    function void sda_low();
        vif.m_sda_oe <= 1'b1;
        vif.m_sda_o  <= 1'b0;
        vif.m_sda_pp <= 1'b0;
    endfunction
    function void sda_pp(bit b);
        vif.m_sda_oe <= 1'b1;
        vif.m_sda_o  <= b;
        vif.m_sda_pp <= 1'b1;
    endfunction
    function void sda_od(bit b);
        vif.m_sda_oe <= !b;
        vif.m_sda_o  <= 1'b0;
        vif.m_sda_pp <= 1'b0;
    endfunction

    // SCL falls, SDA set (mode 0 release, 1 push-pull, 2 open-drain), SCL rises
    task bit_low(int mode, bit val);
        tick(); vif.m_scl_o <= 1'b0;
        tick();
        case (mode)
            1:       sda_pp(val);
            2:       sda_od(val);
            default: sda_release();
        endcase
        repeat (cfg.t_low - 2) tick();
        tick(); vif.m_scl_o <= 1'b1;
    endtask
    task bit_high(output bit smp);
        tick();
        smp = s_sda;
    endtask
    task bit_rest();
        repeat (cfg.t_high - 1) tick();
    endtask
    task bit_cycle(int mode, bit val, output bit smp);
        bit_low(mode, val);
        bit_high(smp);
        bit_rest();
    endtask

    // START from a free bus (SCL high). A target may already hold SDA low
    // (its START request): pulling it too changes nothing.
    task do_start();
        tick(); sda_low();
        repeat (cfg.t_high) tick();
    endtask
    // repeated START, from SCL high
    task do_rstart();
        tick(); vif.m_scl_o <= 1'b0;
        tick(); sda_release();
        repeat (cfg.t_low - 2) tick();
        tick(); vif.m_scl_o <= 1'b1;
        tick(); sda_low();
        repeat (cfg.t_high) tick();
    endtask
    // STOP, from SCL high (after a bit, or after an abort's Sr)
    task do_stop();
        tick(); vif.m_scl_o <= 1'b0;
        tick(); sda_low();
        repeat (cfg.t_low - 2) tick();
        tick(); vif.m_scl_o <= 1'b1;
        tick();
        tick(); sda_release();
        repeat (cfg.t_buf) tick();
    endtask

    // ------------------------------------------------------------ fields
    // header: open-drain (after START, arbitrated) or push-pull (after Sr);
    // returns what was on the bus
    task send_hdr(bit [6:0] a, bit rnw, bit od, output bit [7:0] got);
        bit [7:0] h = {a, rnw};
        bit       lost = 0;
        bit       b;
        for (int i = 7; i >= 0; i--) begin
            bit_cycle(lost ? 0 : (od ? 2 : 1), h[i], b);
            got[i] = b;
            if (h[i] && !b) lost = 1;
        end
    endtask

    task get_ack(output bit ack);
        bit b;
        bit_cycle(0, 1'b0, b);
        ack = !b;
    endtask

    task put_ack(bit ack);
        bit b;
        bit_cycle(ack ? 2 : 0, 1'b0, b);
    endtask

    task write_byte(bit [7:0] v, bit bad_par = 0);
        bit b;
        for (int i = 7; i >= 0; i--) bit_cycle(1, v[i], b);
        bit_cycle(1, i3c_par8(v) ^ bad_par, b);
    endtask

    // one byte + T from the target. With T=1 (more data) and stop_if_more,
    // abort with a repeated START inside the T-bit's high phase.
    task read_byte(output bit [7:0] v, output bit t, input bit stop_if_more);
        bit b;
        for (int i = 7; i >= 0; i--) begin
            bit_cycle(0, 1'b0, b);
            v[i] = b;
        end
        bit_low(0, 1'b0);
        bit_high(t);
        if (t && stop_if_more) sda_low();
        bit_rest();
    endtask

    // up to max bytes; returns 1 when the read was aborted (bus is after Sr)
    task read_bytes(int unsigned max, ref bit [7:0] q[$], output bit t_end, output bit aborted);
        bit [7:0] v;
        bit       t;
        t_end   = 0;
        aborted = 0;
        for (int k = 0; k < max; k++) begin
            read_byte(v, t, k == max - 1);
            q.push_back(v);
            if (!t) begin t_end = 1; return; end
        end
        aborted = (max > 0);
    endtask

    // ------------------------------------------------------------ target requests
    // A target won the header after our START: IBI ({DA, 1}) or Hot-Join
    // ({7'h02, 0}). Answer it; returns whether it was NACKed.
    task serve_target(bit [7:0] got, output bit nacked);
        odve_i3c_item ev = odve_i3c_item::type_id::create("ev");
        bit is_ibi = got[0];
        bit is_hj  = (got[7:1] == I3C_HJ_ADDR) && !got[0];
        bit ack    = is_ibi ? cfg.ibi_ack : (is_hj ? cfg.hj_ack : 1'b0);
        bit t_end, aborted;
        ev.kind = is_hj ? I3C_HOTJOIN : I3C_IBI;
        ev.addr = got[7:1];
        ev.rnw  = got[0];
        ev.ack  = ack;
        put_ack(ack);
        aborted = 0;
        if (is_ibi && ack && (da_bcr.exists(got[7:1]) ? da_bcr[got[7:1]][2] : 1'b1)) begin
            read_bytes(cfg.ibi_max_len, ev.data, t_end, aborted);
            ev.t_end = t_end;
        end
        if (is_ibi) begin if (ack) n_ibi_ack++; else n_ibi_nack++; end
        else if (is_hj) begin if (ack) n_hj_ack++; else n_hj_nack++; end
        `uvm_info(get_name(), {"served ", ev.convert2string()}, UVM_MEDIUM)
        evt_port.write(ev);
        nacked = !ack;
    endtask

    // the bus is idle and a target pulled SDA low: run the arbitrated header
    task serve_idle_request();
        bit [7:0] got;
        bit       nacked, ack;
        sda_low();
        repeat (cfg.t_high - 1) tick();
        send_hdr(I3C_BCAST, 1'b0, 1'b1, got);
        if (got != {I3C_BCAST, 1'b0}) serve_target(got, nacked);
        else get_ack(ack);
        do_stop();
    endtask

    // ------------------------------------------------------------ items
    task execute(odve_i3c_item it);
        bit [7:0] got;
        bit       after_sr = 0;
        bit       nacked, ack, t_end, aborted;
        bit [6:0] h_addr;
        bit       h_rnw;
        bit       is_priv = it.kind inside {I3C_PRIV_WR, I3C_PRIV_RD};

        it.ack = 0;
        it.t_end = 0;
        if (it.kind == I3C_PRIV_RD || it.kind == I3C_CCC_DR) it.data.delete();
        h_addr = (is_priv && !it.use_7e) ? it.addr : I3C_BCAST;
        h_rnw  = (is_priv && !it.use_7e) ? (it.kind == I3C_PRIV_RD) : 1'b0;

        // first header, retried as long as targets win it
        forever begin
            if (!after_sr) do_start();
            send_hdr(h_addr, h_rnw, !after_sr, got);
            if (after_sr || got == {h_addr, h_rnw}) break;
            serve_target(got, nacked);
            if (nacked) begin do_rstart(); after_sr = 1; end
            else        begin do_stop();   after_sr = 0; end
        end
        get_ack(ack);
        aborted = 0;

        case (it.kind)
            I3C_PRIV_WR, I3C_PRIV_RD: begin
                if (it.use_7e && ack) begin
                    do_rstart();
                    send_hdr(it.addr, it.kind == I3C_PRIV_RD, 1'b0, got);
                    get_ack(ack);
                end
                it.ack = ack;
                if (ack) begin
                    if (it.kind == I3C_PRIV_WR) foreach (it.data[i]) write_byte(it.data[i], i == it.perr_idx);
                    else begin
                        read_bytes(it.len, it.data, t_end, aborted);
                        it.t_end = t_end;
                    end
                end
            end
            I3C_CCC_BC: begin
                it.ack = ack;
                if (ack) begin
                    write_byte(it.ccc);
                    foreach (it.data[i]) write_byte(it.data[i], i == it.perr_idx);
                    if (it.ccc == I3C_CCC_RSTDAA) da_bcr.delete();
                end
            end
            I3C_CCC_DW, I3C_CCC_DR: begin
                if (ack) begin
                    write_byte(it.ccc);
                    do_rstart();
                    send_hdr(it.addr, it.kind == I3C_CCC_DR, 1'b0, got);
                    get_ack(ack);
                    it.ack = ack;
                    if (ack) begin
                        if (it.kind == I3C_CCC_DW) foreach (it.data[i]) write_byte(it.data[i], i == it.perr_idx);
                        else begin
                            read_bytes(it.len, it.data, t_end, aborted);
                            it.t_end = t_end;
                            if (it.ccc == I3C_CCC_GETBCR && it.data.size() > 0) da_bcr[it.addr] = it.data[0];
                        end
                    end
                end
            end
            I3C_ENTDAA: begin
                it.ack = ack;
                it.daa_id.delete(); it.daa_da.delete(); it.daa_par_ok.delete(); it.daa_ack.delete();
                if (ack) begin
                    write_byte(I3C_CCC_ENTDAA);
                    for (int r = 0; r < 17; r++) begin
                        bit [63:0] id;
                        bit [6:0]  da;
                        bit        b, par;
                        do_rstart();
                        send_hdr(I3C_BCAST, 1'b1, 1'b0, got);
                        get_ack(ack);
                        if (!ack) break;
                        for (int i = 63; i >= 0; i--) begin bit_cycle(0, 1'b0, b); id[i] = b; end
                        if (r >= it.da_pool.size()) begin
                            `uvm_error(get_name(), $sformatf("ENTDAA round %0d: a target answered but da_pool has %0d address(es)", r, it.da_pool.size()))
                            da = 7'h7F;
                        end else da = it.da_pool[r];
                        par = ~^da;
                        if (r == it.perr_idx) par = ~par;
                        for (int i = 6; i >= 0; i--) bit_cycle(2, da[i], b);
                        bit_cycle(2, par, b);
                        get_ack(ack);
                        it.daa_id.push_back(id);
                        it.daa_da.push_back(da);
                        it.daa_par_ok.push_back(r != it.perr_idx);
                        it.daa_ack.push_back(ack);
                        if (ack) da_bcr[da] = id[15:8];
                        if (r == 16) `uvm_error(get_name(), "ENTDAA: more than 16 rounds")
                    end
                end
            end
            default: `uvm_error(get_name(), $sformatf("%s is not a controller request", it.kind.name()))
        endcase
        do_stop();
        `uvm_info(get_name(), it.convert2string(), UVM_HIGH)
    endtask

    virtual task run_phase(uvm_phase phase);
        vif.m_scl_o  <= 1'b1;
        vif.m_sda_oe <= 1'b0;
        vif.m_sda_o  <= 1'b0;
        vif.m_sda_pp <= 1'b0;
        wait (vif.rst_n === 1'b1);
        repeat (4) tick();
        forever begin
            seq_item_port.try_next_item(req);
            if (req == null) begin
                tick();
                if (s_scl && !s_sda) serve_idle_request();
            end else begin
                execute(req);
                seq_item_port.item_done();
            end
        end
    endtask
endclass
