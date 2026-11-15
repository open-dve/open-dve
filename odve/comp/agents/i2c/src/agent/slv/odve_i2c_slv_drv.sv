// I2C target (slave role). Samples SCL/SDA at every posedge of vif.clk and
// drives the s_* pulls one cycle after an SCL edge: recognises START /
// repeated START / STOP, its 7-bit address (cfg.addr7), its 10-bit address
// (cfg.addr10: header 11110xx + low byte, and after Sr the header with R
// when it was addressed before - UM10204 3.1.11), the general call
// (cfg.gc_en) and any extra address its model claims; acknowledges, receives
// and transmits bytes, and stretches SCL after an acknowledge when told to.
// Optionally it releases the bus and resets after SCL has been low for
// cfg.t_timeout cycles (SMBus tTIMEOUT).
//
// What to answer comes from a model, per event (odve_i2c_slv_item):
//   ODVE_I2C_SLV_MEM  cfg.model.handle(ev) - the model lives in the driver
//   ODVE_I2C_SLV_SEQ  the event goes out on req_port (the slave sequencer's
//                     req_fifo) and the answer comes back as a sequence
//                     item from the responding sequence, zero time later.
class odve_i2c_slv_drv extends uvm_driver #(odve_i2c_slv_item);
    `uvm_component_utils(odve_i2c_slv_drv)

    virtual odve_i2c_if vif;
    odve_i2c_cfg        cfg;
    uvm_analysis_port #(odve_i2c_slv_item) req_port;

    typedef enum { S_IDLE, S_RX, S_RX_ACK, S_TX, S_TX_ACK, S_WAIT } state_e;

    int unsigned n_events = 0, n_timeouts = 0;

    protected state_e      st = S_IDLE;
    protected bit          busy, first, a10_hdr, matched10, addressed, in_xfer, ack_q, tx_next, restart, inbyte;
    protected int unsigned bitcnt, idx, str_next, str_cnt, lowcnt, ntx;
    protected bit [7:0]    sh;

    function new(string name = "odve_i2c_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
    endfunction

    task scl_drv(bit v);
        vif.s_scl_oe <= !v;
        vif.s_scl_o  <= 1'b0;
    endtask

    task sda_drv(bit v);
        vif.s_sda_oe <= !v;
        vif.s_sda_o  <= 1'b0;
    endtask

    // Ask the model (MEM) or the responding sequence (SEQ); zero time.
    task respond(odve_i2c_slv_item ev);
        odve_i2c_slv_item rsp;
        n_events++;
        if (cfg.slv_mode == ODVE_I2C_SLV_MEM) begin
            cfg.model.handle(ev);
        end else begin
            req_port.write(ev);
            seq_item_port.get_next_item(rsp);
            ev.ack     = rsp.ack;
            ev.data    = rsp.data;
            ev.stretch = rsp.stretch;
            seq_item_port.item_done();
        end
        `uvm_info(get_name(), ev.convert2string(), UVM_HIGH)
    endtask

    task ev_addr(bit [9:0] a, bit a10, bit rw, bit gc);
        odve_i2c_slv_item ev = odve_i2c_slv_item::type_id::create("ev");
        ev.ev = I2C_EV_ADDR; ev.addr = a; ev.addr10 = a10; ev.rw = rw; ev.gc = gc; ev.restart = restart;
        respond(ev);
        ack_q     = ev.ack;
        addressed = ev.ack;
        ntx       = 0;
        tx_next   = rw && ev.ack;
        str_next  = ev.stretch;
        idx       = 0;
        if (ev.ack) in_xfer = 1;
    endtask

    task ev_stop(bit abort, bit tmo);
        odve_i2c_slv_item ev;
        if (!in_xfer) return;
        ev = odve_i2c_slv_item::type_id::create("ev");
        ev.ev = I2C_EV_STOP; ev.abort = abort; ev.tmo = tmo; ev.nrd = ntx;
        respond(ev);
        in_xfer = 0;
    endtask

    // the next byte to transmit: load it and put its MSB on SDA
    task load_tx();
        odve_i2c_slv_item ev = odve_i2c_slv_item::type_id::create("ev");
        ev.ev = I2C_EV_READ; ev.idx = idx;
        respond(ev);
        idx++;
        sh = ev.data;
        if (ev.stretch > str_next) str_next = ev.stretch;
        sda_drv(sh[7]);
        bitcnt = 0;
        st = S_TX;
    endtask

    // 8 bits received: decide the acknowledge
    task byte_rx(bit [7:0] b);
        tx_next = 0;
        str_next = 0;
        ack_q = 0;
        if (first) begin
            first = 0;
            addressed = 0;
            if (b[7:3] == 5'b11110) begin
                if (cfg.en_addr10 && b[2:1] == cfg.addr10[9:8]) begin
                    if (!b[0]) begin
                        ack_q   = 1;          // A1; the low byte decides (A2)
                        a10_hdr = 1;
                    end else if (matched10 && restart) begin
                        ev_addr(cfg.addr10, 1, 1, 0);
                    end
                end
            end else if (b == 8'h00) begin
                if (cfg.gc_en) ev_addr(10'h000, 0, 0, 1);
            end else if ((cfg.en_addr7 && b[7:1] == cfg.addr7) || (cfg.model != null && cfg.model.claims(b[7:1]))) begin
                ev_addr({3'b000, b[7:1]}, 0, b[0], 0);
            end
        end else if (a10_hdr) begin
            a10_hdr = 0;
            if (b == cfg.addr10[7:0]) begin
                ev_addr(cfg.addr10, 1, 0, 0);
                matched10 = ack_q;
            end
        end else if (addressed) begin
            odve_i2c_slv_item ev = odve_i2c_slv_item::type_id::create("ev");
            ev.ev = I2C_EV_WRITE; ev.data = b; ev.idx = idx;
            respond(ev);
            idx++;
            ack_q    = ev.ack;
            str_next = ev.stretch;
        end
    endtask

    task release_all();
        sda_drv(1);
        scl_drv(1);
        str_cnt = 0;
    endtask

    virtual task run_phase(uvm_phase phase);
        bit scl, sda, pscl = 1, psda = 1, rise, fall, start_c, stop_c;
        release_all();
        forever begin
            @(posedge vif.clk);
            scl = (vif.scl === 1'b1);
            sda = (vif.sda === 1'b1);
            if (vif.rst_n !== 1'b1) begin
                release_all();
                busy = 0; st = S_IDLE; in_xfer = 0; matched10 = 0;
                pscl = scl; psda = sda;
                continue;
            end
            rise    = scl && !pscl;
            fall    = !scl && pscl;
            start_c = scl && pscl && psda && !sda;
            stop_c  = scl && pscl && !psda && sda;
            pscl = scl;
            psda = sda;

            if (str_cnt != 0) begin
                str_cnt--;
                if (str_cnt == 0) scl_drv(1);
            end

            // SMBus clock-low timeout: release everything, back to idle
            if (cfg.t_timeout != 0 && busy && !scl) begin
                lowcnt++;
                if (lowcnt >= cfg.t_timeout) begin
                    `uvm_info(get_name(), $sformatf("SCL low %0d cycles: timeout, interface reset", lowcnt), UVM_MEDIUM)
                    n_timeouts++;
                    release_all();
                    ev_stop(1, 1);
                    busy = 0; st = S_IDLE; matched10 = 0; lowcnt = 0;
                    continue;
                end
            end else begin
                lowcnt = 0;
            end

            if (start_c) begin
                if (busy && in_xfer && ((st == S_RX && inbyte) || (st == S_TX && bitcnt != 0))) ev_stop(1, 0);
                release_all();
                restart = busy;
                busy  = 1;
                first = 1;
                a10_hdr = 0;
                st = S_RX;
                bitcnt = 0;
                inbyte = 0;
                continue;
            end
            if (stop_c) begin
                if (busy) ev_stop((st == S_RX && inbyte) || (st == S_TX && bitcnt != 0), 0);
                release_all();
                busy = 0; st = S_IDLE; matched10 = 0; in_xfer = 0;
                continue;
            end
            if (!busy) continue;

            case (st)
                S_RX: begin
                    if (rise) begin
                        sh = {sh[6:0], sda};
                        bitcnt++;
                        if (bitcnt == 8) byte_rx(sh);
                    end
                    if (fall) begin
                        if (bitcnt == 8) begin
                            sda_drv(!ack_q);
                            st = S_RX_ACK;
                            bitcnt = 0;
                            inbyte = 0;
                        end else if (bitcnt != 0) begin
                            inbyte = 1;
                        end
                    end
                end
                S_RX_ACK: if (fall) begin
                    sda_drv(1);
                    if (!ack_q) begin
                        st = S_WAIT;
                    end else begin
                        if (tx_next) load_tx();
                        else begin st = S_RX; bitcnt = 0; end
                        if (str_next != 0) begin
                            scl_drv(0);
                            str_cnt = str_next;
                        end
                    end
                end
                S_TX: if (fall) begin
                    bitcnt++;
                    if (bitcnt == 8) begin
                        sda_drv(1);
                        ntx++;
                        st = S_TX_ACK;
                    end else begin
                        sda_drv(sh[7 - bitcnt]);
                    end
                end
                S_TX_ACK: begin
                    if (rise) ack_q = !sda;        // the controller's acknowledge
                    if (fall) begin
                        if (!ack_q) st = S_WAIT;
                        else begin
                            str_next = 0;
                            load_tx();
                            if (str_next != 0) begin
                                scl_drv(0);
                                str_cnt = str_next;
                            end
                        end
                    end
                end
                default: ;   // S_WAIT / S_IDLE: until START or STOP
            endcase
        end
    endtask
endclass
