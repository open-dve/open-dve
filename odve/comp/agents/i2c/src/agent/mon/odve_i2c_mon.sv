// Passive observer of the I2C bus. Samples SCL/SDA at every posedge of
// vif.clk (oversampling, like a hardware target), reconstructs each
// transfer from START to STOP - segments separated by repeated STARTs,
// 7-bit, 10-bit and general-call addressing, ACK/NACK of every byte - and
// publishes one odve_i2c_item per transfer on item_collected_port.
//
// Protocol checks (uvm_error, id I2C_BUS_ERR; a test that provokes them on
// purpose demotes the id and checks n_bus_err):
//   * START/STOP inside a byte (UM10204 3.1.3/3.1.5: SDA changes only while
//     SCL is LOW, every byte has 8 bits + acknowledge)
//   * SDA ownership: during a bit only its transmitter may pull SDA, during
//     the acknowledge only the receiver (per-party pulls of the interface)
//   * the controller-receiver must NACK the last byte it reads (3.1.6 #5)
// Timing checks (id I2C_TIMING) against cfg.min_*: tLOW, tHIGH, tHD;STA,
// tSU;STO, tBUF, in clk cycles.
class odve_i2c_mon_seg;
    bit [9:0] addr;
    bit       addr10, rw, gc, addr_ack = 1;
    int       nb = 0;          // bytes in this segment, address bytes included
    bit [7:0] wdata[$];
    bit       wack[$];
    bit [7:0] rdata[$];
    bit       mack[$];
endclass

class odve_i2c_mon extends uvm_monitor;
    `uvm_component_utils(odve_i2c_mon)

    uvm_analysis_port #(odve_i2c_item) item_collected_port;
    virtual odve_i2c_if vif;
    odve_i2c_cfg        cfg;

    int unsigned n_seen = 0, n_bus_err = 0, n_timing_err = 0, n_aborted = 0, n_stretched = 0;

    `odve_cov_create(odve_i2c_cg)

    // reconstruction state
    local bit          busy, ign, seen_stop, aborted, stretched, pend_own;
    local int unsigned bitcnt, nfall, hd_cnt, max_low;
    local bit [7:0]    sh;
    local odve_i2c_mon_seg segs[$];
    local odve_i2c_mon_seg seg;
    local bit [9:0]    last_a10;   // 10-bit address of the previous segment (for Sr + header R)

    function new(string name = "odve_i2c_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void bus_err(string msg);
        n_bus_err++;
        `uvm_error("I2C_BUS_ERR", msg)
    endfunction

    function void timing_err(string msg);
        n_timing_err++;
        `uvm_error("I2C_TIMING", msg)
    endfunction

    function void new_segment();
        seg = new();
        segs.push_back(seg);
        bitcnt = 0;
        nfall  = 0;
        ign    = 0;
    endfunction

    // Is the byte in flight sent by the controller? Address bytes always,
    // data bytes when the segment writes.
    function bit mst_tx();
        if (seg == null) return 1;
        if (seg.nb == 0) return 1;
        if (seg.addr10 && !seg.rw && seg.nb == 1) return 1;
        return !seg.rw;
    endfunction

    // A complete byte (8 bits) and its acknowledge (ack = SDA low at the 9th clock).
    function void byte_done(bit [7:0] b, bit ack);
        if (seg.nb == 0) begin
            if (b[7:3] == 5'b11110) begin
                seg.addr10 = 1;
                seg.rw     = b[0];
                seg.addr   = {b[2:1], 8'h00};
                if (b[0]) begin
                    // Sr + header R: the target addressed by the previous segment
                    if (segs.size() > 1 && segs[segs.size() - 2].addr10 && last_a10[9:8] == b[2:1]) seg.addr = last_a10;
                    else bus_err($sformatf("10-bit read header 0x%02h without a preceding 10-bit write address", b));
                end
            end else begin
                seg.addr = {3'b000, b[7:1]};
                seg.rw   = b[0];
                seg.gc   = (b == 8'h00);
            end
            seg.addr_ack = ack;
        end else if (seg.addr10 && !seg.rw && seg.nb == 1) begin
            seg.addr[7:0] = b;
            seg.addr_ack  = seg.addr_ack && ack;
            last_a10      = seg.addr;
        end else if (!seg.rw) begin
            seg.wdata.push_back(b);
            seg.wack.push_back(ack);
        end else begin
            seg.rdata.push_back(b);
            seg.mack.push_back(ack);
        end
        seg.nb++;
        if (!ack) ign = 1;   // NACK: the controller must now STOP or repeat START
    endfunction

    function void finish();
        odve_i2c_item tr;
        odve_i2c_mon_seg s0, s1;
        int special;
        if (segs.size() == 0 || segs[0].nb == 0) begin
            segs.delete();
            return;
        end
        tr = odve_i2c_item::type_id::create("tr");
        s0 = segs[0];
        tr.addr       = s0.addr;
        tr.addr10     = s0.addr10;
        tr.addr_ack   = s0.addr_ack;
        tr.wdata      = s0.wdata;
        tr.wack       = s0.wack;
        tr.is_gc      = s0.gc && !s0.rw;
        tr.aborted    = aborted;
        tr.stretched  = stretched;
        tr.max_scl_low = max_low;
        if (segs.size() == 1) begin
            tr.kind  = s0.rw ? I2C_READ : I2C_WRITE;
            tr.rdata = s0.rdata;
        end else begin
            s1 = segs[1];
            if (segs.size() > 2 || s0.rw || !s1.rw)
                `uvm_warning(get_name(), $sformatf("transfer with %0d segments (%s then %s): only the first two are reported", segs.size(), s0.rw ? "R" : "W", s1.rw ? "R" : "W"))
            tr.kind     = (s0.addr10 && s0.wdata.size() == 0) ? I2C_READ : I2C_WRITE_READ;
            tr.addr_ack = s0.addr_ack && s1.addr_ack;
            tr.rdata    = s1.rdata;
            if (s1.mack.size() > 0) tr.mack_last = s1.mack[s1.mack.size() - 1];
        end
        if (segs.size() == 1 && s0.mack.size() > 0) tr.mack_last = s0.mack[s0.mack.size() - 1];
        tr.nrd = tr.rdata.size();
        foreach (tr.wack[i]) if (!tr.wack[i]) tr.wr_nack = 1;
        if (tr.mack_last && !aborted && !(cfg.t_timeout != 0 && max_low >= cfg.t_timeout))
            bus_err($sformatf("controller ACKed the last byte it read before STOP: %s", tr.convert2string()));
        segs.delete();
        n_seen++;
        if (tr.aborted)   n_aborted++;
        if (tr.stretched) n_stretched++;
        special = tr.aborted ? 2 : tr.is_gc ? 1 : 0;
        `uvm_info(get_name(), tr.convert2string(), UVM_HIGH)
        `odve_cov_sample(odve_i2c_cg, int'(tr.kind), tr.addr10, int'(tr.wdata.size()), int'(tr.rdata.size()), tr.addr_ack, tr.wr_nack, special, tr.stretched)
        item_collected_port.write(tr);
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit scl, sda, pscl = 1, psda = 1, rise, fall, start_c, stop_c, ack;
        int unsigned lowcnt = 0, hicnt = 0, idle = 0;
        forever begin
            @(posedge vif.clk);
            scl = (vif.scl === 1'b1);
            sda = (vif.sda === 1'b1);
            if (vif.rst_n !== 1'b1) begin
                busy = 0; segs.delete(); seg = null; seen_stop = 0;
                pscl = scl; psda = sda; lowcnt = 0; hicnt = 0; idle = 0;
                continue;
            end
            rise    = scl && !pscl;
            fall    = !scl && pscl;
            start_c = scl && pscl && psda && !sda;
            stop_c  = scl && pscl && !psda && sda;

            if (busy && vif.t_scl_pull === 1'b1) stretched = 1;
            if (rise && busy) begin
                if (cfg.min_t_low != 0 && lowcnt < cfg.min_t_low)
                    timing_err($sformatf("tLOW %0d cycles < %0d", lowcnt, cfg.min_t_low));
                if (lowcnt > max_low) max_low = lowcnt;
            end
            if (fall && busy) begin
                if (hd_cnt != 0) begin
                    if (cfg.min_t_hd_sta != 0 && hd_cnt < cfg.min_t_hd_sta)
                        timing_err($sformatf("tHD;STA %0d cycles < %0d", hd_cnt, cfg.min_t_hd_sta));
                    hd_cnt = 0;
                end else if (cfg.min_t_high != 0 && hicnt < cfg.min_t_high) begin
                    timing_err($sformatf("tHIGH %0d cycles < %0d", hicnt, cfg.min_t_high));
                end
            end

            if (start_c) begin
                if (busy) begin
                    if (nfall != 0 && !ign) begin
                        aborted = 1;
                        bus_err($sformatf("repeated START inside a byte (after %0d bits)", bitcnt));
                    end
                end else begin
                    if (seen_stop && cfg.min_t_buf != 0 && idle < cfg.min_t_buf)
                        timing_err($sformatf("tBUF %0d cycles < %0d", idle, cfg.min_t_buf));
                    aborted = 0; stretched = 0; max_low = 0;
                    segs.delete();
                end
                busy   = 1;
                hd_cnt = 1;
                new_segment();
            end else if (stop_c) begin
                if (busy) begin
                    if (cfg.min_t_su_sto != 0 && hicnt < cfg.min_t_su_sto)
                        timing_err($sformatf("tSU;STO %0d cycles < %0d", hicnt, cfg.min_t_su_sto));
                    if (nfall != 0 && !ign) begin
                        aborted = 1;
                        bus_err($sformatf("STOP inside a byte (after %0d bits)", bitcnt));
                    end
                    finish();
                end
                busy = 0; seen_stop = 1; seg = null; pend_own = 0;
            end else if (busy && !ign) begin
                if (rise) begin
                    bitcnt++;
                    if (bitcnt <= 8) begin
                        sh = {sh[6:0], sda};
                        // only the transmitter of this bit may pull SDA - except
                        // the controller preparing a STOP right after a read
                        // address (SMBus Quick Command read): judged at the fall
                        if (bitcnt == 1 && !mst_tx() && vif.m_sda_pull === 1'b1 && vif.t_sda_pull !== 1'b1)
                            pend_own = 1;
                        else if (mst_tx() ? vif.t_sda_pull === 1'b1 : vif.m_sda_pull === 1'b1)
                            bus_err($sformatf("%s pulls SDA during bit %0d sent by the %s", mst_tx() ? "target" : "controller", 8 - bitcnt, mst_tx() ? "controller" : "target"));
                    end else begin
                        // acknowledge: only the receiver may pull SDA
                        if (mst_tx() ? vif.m_sda_pull === 1'b1 : vif.t_sda_pull === 1'b1)
                            bus_err($sformatf("%s (the transmitter) pulls SDA during the acknowledge", mst_tx() ? "controller" : "target"));
                        ack = !sda;
                        byte_done(sh, ack);
                    end
                end
                if (fall) begin
                    if (pend_own) begin
                        pend_own = 0;
                        bus_err("controller pulls SDA during bit 7 sent by the target");
                    end
                    if (bitcnt >= 9) begin
                        bitcnt = 0;
                        nfall  = 0;
                    end else if (bitcnt >= 1) begin
                        nfall++;
                    end
                end
            end

            // run lengths, for the next sample's checks
            if (scl) begin hicnt++; lowcnt = 0; end else begin lowcnt++; hicnt = 0; end
            if (busy && scl && !sda && hd_cnt != 0 && !start_c) hd_cnt++;
            if (!busy && scl && sda) idle++; else idle = 0;
            if (busy && !scl && lowcnt > max_low) max_low = lowcnt;
            pscl = scl;
            psda = sda;
        end
    endtask
endclass
