// I2C controller (master role). Generates SCL and the START / repeated
// START / STOP conditions, transmits address and data bytes MSB first,
// samples the target's acknowledge, reads bytes and acknowledges them (NACK
// on the last one). Everything happens at posedge vif.clk with non-blocking
// writes of the m_* pulls; SDA is changed half way through SCL low and
// sampled at the end of SCL high. After releasing SCL it waits until the
// line is really high, so a target may stretch the clock (UM10204 3.1.9).
//
// The item's results are written back into it: addr_ack, wack[], wr_nack,
// rdata[]. A NACK ends the transfer with a STOP. Error injection:
// abort_byte/abort_bit (STOP inside a written byte) and tmo_byte/tmo_cycles
// (hold SCL low after a byte, then STOP - an SMBus clock-low timeout).
class odve_i2c_mst_drv_base extends uvm_driver #(odve_i2c_item);
    `uvm_component_utils(odve_i2c_mst_drv_base)

    virtual odve_i2c_if vif;
    odve_i2c_cfg        cfg;

    int unsigned n_items = 0;
    protected int  bidx;       // byte index in the transfer (address bytes included)
    protected bit  stopped;    // the transfer was ended early (abort / timeout injection)
    protected odve_i2c_item it;

    function new(string name = "odve_i2c_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task cyc(int unsigned n);
        repeat (n) @(posedge vif.clk);
    endtask

    // 1 = release (the pull-up makes it high), 0 = pull low
    task scl_drv(bit v);
        vif.m_scl_oe <= !v;
        vif.m_scl_o  <= 1'b0;
    endtask

    task sda_drv(bit v);
        vif.m_sda_oe <= !v;
        vif.m_sda_o  <= 1'b0;
    endtask

    task wait_scl_high();
        cyc(1);
        while (vif.scl !== 1'b1) cyc(1);
    endtask

    // SCL was pulled low at the last edge. One clock: b on SDA in the middle
    // of the low phase, SCL released (and waited for), SDA sampled at the end
    // of the high phase into smp, SCL pulled low. chk: b is ours, a 1 that
    // reads back 0 means someone else drives SDA (lost arbitration).
    task clock_bit(bit b, bit chk, output bit smp);
        cyc(cfg.t_low / 2);
        sda_drv(b);
        cyc(cfg.t_low - cfg.t_low / 2);
        scl_drv(1);
        wait_scl_high();
        if (cfg.t_high > 1) cyc(cfg.t_high - 1);
        smp = (vif.sda === 1'b1);
        if (chk && b && !smp)
            `uvm_error("I2C_ARB", $sformatf("SDA low while transmitting a 1 (byte %0d): another device drives SDA - lost arbitration", bidx))
        scl_drv(0);
    endtask

    task do_start();
        int unsigned n = 0;
        while (n < cfg.t_buf) begin       // bus free: both lines high for tBUF
            cyc(1);
            n = (vif.scl === 1'b1 && vif.sda === 1'b1) ? n + 1 : 0;
        end
        sda_drv(0);
        cyc(cfg.t_hd_sta);
        scl_drv(0);
    endtask

    task do_rstart();
        cyc(cfg.t_low / 2);
        sda_drv(1);
        cyc(cfg.t_low - cfg.t_low / 2);
        scl_drv(1);
        wait_scl_high();
        if (cfg.t_su_sta > 1) cyc(cfg.t_su_sta - 1);
        if (vif.sda !== 1'b1) `uvm_error("I2C_BUS", "repeated START: SDA is held low by another device")
        sda_drv(0);
        cyc(cfg.t_hd_sta);
        scl_drv(0);
    endtask

    task do_stop();
        cyc(cfg.t_low / 2);
        sda_drv(0);
        cyc(cfg.t_low - cfg.t_low / 2);
        scl_drv(1);
        wait_scl_high();
        if (cfg.t_su_sto > 1) cyc(cfg.t_su_sto - 1);
        sda_drv(1);
        cyc(1);
        if (vif.sda !== 1'b1) begin
            `uvm_error("I2C_BUS", "STOP: SDA is held low by another device (a target still transmitting?)")
            while (vif.sda !== 1'b1) cyc(1);
        end
        stopped = 1;
    endtask

    // After a byte's acknowledge: the clock-low timeout injection.
    task after_byte();
        if (it.tmo_byte >= 0 && bidx == it.tmo_byte) begin
            `uvm_info(get_name(), $sformatf("holding SCL low %0d cycles after byte %0d", it.tmo_cycles, bidx), UVM_MEDIUM)
            cyc(it.tmo_cycles);
            do_stop();
        end
        bidx++;
    endtask

    task wr_byte(bit [7:0] b, output bit ack);
        bit s;
        ack = 0;
        for (int i = 7; i >= 0; i--) begin
            if (it.abort_byte >= 0 && bidx == it.abort_byte && 7 - i == int'(it.abort_bit)) begin
                `uvm_info(get_name(), $sformatf("STOP after %0d bits of byte %0d", it.abort_bit, bidx), UVM_MEDIUM)
                do_stop();
                return;
            end
            clock_bit(b[i], 1, s);
        end
        clock_bit(1'b1, 0, s);
        ack = !s;
        after_byte();
    endtask

    // Address phase: 7-bit {addr, rw}; 10-bit header 11110 a[9:8] rw, and
    // for a write the low address byte. NACK -> STOP, returns 0.
    task send_addr(bit rw, bit hdr_only, output bit ok);
        bit ack;
        ok = 0;
        if (!it.addr10) begin
            wr_byte({it.addr[6:0], rw}, ack);
        end else begin
            wr_byte({5'b11110, it.addr[9:8], rw}, ack);
            if (!stopped && ack && !hdr_only) wr_byte(it.addr[7:0], ack);
        end
        if (stopped) return;
        it.addr_ack = ack;
        if (!ack) begin
            do_stop();
            return;
        end
        ok = 1;
    endtask

    task drive(odve_i2c_item t);
        bit ok, ack, need_w;
        bit [7:0] b;
        int unsigned n, i;
        it = t;
        bidx = 0;
        stopped = 0;
        it.addr_ack = 0;
        it.wr_nack = 0;
        it.wack.delete();
        it.rdata.delete();
        need_w = (it.kind != I2C_READ) || it.addr10;

        do_start();
        if (need_w) begin
            send_addr(0, 0, ok);
            if (!ok) return;
            if (it.kind != I2C_READ) begin
                foreach (it.wdata[k]) begin
                    wr_byte(it.wdata[k], ack);
                    if (stopped) return;
                    it.wack.push_back(ack);
                    if (!ack) begin
                        it.wr_nack = 1;
                        do_stop();
                        return;
                    end
                end
            end
            if (it.kind == I2C_WRITE) begin
                do_stop();
                return;
            end
            do_rstart();
            send_addr(1, 1, ok);
            if (!ok) return;
        end else begin
            send_addr(1, 0, ok);
            if (!ok) return;
        end
        // read phase: ACK every byte but the last
        n = it.rd_count_hdr ? 1 : it.nrd;
        i = 0;
        while (i < n) begin
            for (int k = 7; k >= 0; k--) begin
                bit s;
                clock_bit(1'b1, 0, s);
                b[k] = s;
            end
            it.rdata.push_back(b);
            if (i == 0 && it.rd_count_hdr) n = 1 + b + it.rd_extra;
            i++;
            begin
                bit s;
                clock_bit(!(i < n), 0, s);
            end
            after_byte();
            if (stopped) return;
        end
        do_stop();
    endtask

    virtual task run_phase(uvm_phase phase);
        scl_drv(1);
        sda_drv(1);
        wait (vif.rst_n === 1'b1);
        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info(get_name(), {"start ", req.convert2string()}, UVM_HIGH)
            drive(req);
            n_items++;
            `uvm_info(get_name(), {"done  ", req.convert2string()}, UVM_HIGH)
            seq_item_port.item_done();
        end
    endtask
endclass
