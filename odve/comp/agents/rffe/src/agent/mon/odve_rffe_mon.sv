// Passive RFFE observer. Oversamples SCLK/SDATA at every TB clock (the same
// way the RTL slave does), finds each Sequence Start Condition, decodes the
// command frame and follows the sequence it announces: address frames, write
// data frames or the read turnaround + slave data frames, bus park. One item
// per complete sequence on item_collected_port, sampled into odve_rffe_cg.
//
// Protocol checks (UVM_ERROR):
//   - more than one SDATA driver enabled at once (contention)
//   - SDATA changing at the SCLK falling edge it is sampled at (setup)
//   - a master frame not driven by the master, or the master driving during
//     the slave's read data frames (turnaround)
//   - a parity error in a master frame (cfg.chk_parity) or in read data
//     (an NRF - all nine bits 0 - is not a parity error)
//   - a bus park cycle that is not 0
//   - a read command addressed to the broadcast USID 0
//   - an unsupported command code, an SSC inside a sequence
class odve_rffe_mon extends uvm_monitor;
    `uvm_component_utils(odve_rffe_mon)

    uvm_analysis_port #(odve_rffe_item) item_collected_port;
    virtual odve_rffe_if vif;
    odve_rffe_cfg        cfg;
    int unsigned n_seen = 0;

    // sampler state
    bit          sc, sc_q, sd, sd_q, armed, rise, fall, ssc_now;
    bit [3:0]    oe, oe_q;
    int unsigned t = 0, t_rise = 0, per = 0;
    bit          dir_prev = 0;

    `odve_cov_create(odve_rffe_cg)

    function new(string name = "odve_rffe_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    // one TB clock: update the edge / SSC detection
    task sample();
        @(posedge vif.clk);
        sc_q = sc;
        sd_q = sd;
        oe_q = oe;
        sc   = (vif.sclk === 1'b1);
        sd   = (vif.sdata === 1'b1);
        oe   = vif.oe_all;
        t++;
        if (vif.rst_n !== 1'b1) begin
            armed = 0; rise = 0; fall = 0; ssc_now = 0;
            return;
        end
        if ($countones(oe) > 1)
            `uvm_error(get_name(), $sformatf("SDATA contention: drivers %b enabled at once", oe))
        rise    = sc && !sc_q;
        fall    = !sc && sc_q;
        ssc_now = 0;
        if (rise) begin
            per    = t - t_rise;
            t_rise = t;
            armed  = 0;
        end else if (!sc && !sc_q && sd && !sd_q) begin
            armed = 1;
        end else if (!sc && !sc_q && !sd && sd_q && armed) begin
            armed   = 0;
            ssc_now = 1;
        end
    endtask

    // next bit (sampled at the SCLK falling edge); abort = an SSC came first
    task get_bit(output bit b, output bit [3:0] drv, output bit abort);
        abort = 0;
        forever begin
            sample();
            if (ssc_now) begin abort = 1; return; end
            if (fall) break;
        end
        if (sd != sd_q)
            `uvm_error(get_name(), "SDATA changed at the SCLK falling edge it is sampled at")
        b   = sd;
        drv = oe_q;      // who drove the bit while SCLK was high
    endtask

    // n bits MSB first; drv = OR of the drivers of all bits; lastper = the
    // SCLK period ending at the last bit's rising edge
    task get_bits(int n, output bit [12:0] v, output bit [3:0] drv, output int unsigned lastper, output bit abort);
        bit b;
        bit [3:0] d;
        v = '0; drv = '0; lastper = 0;
        for (int i = 0; i < n; i++) begin
            get_bit(b, d, abort);
            if (abort) return;
            v   = {v[11:0], b};
            drv = drv | d;
            lastper = per;
        end
    endtask

    function void chk_master_frame(string what, bit [3:0] drv);
        if (drv != 4'b0001)
            `uvm_error(get_name(), $sformatf("%s not driven by the master alone (drivers %b)", what, drv))
    endfunction

    // the bus park cycle: one bit, must be 0
    task get_bpc(string who, output bit abort);
        bit b;
        bit [3:0] d;
        get_bit(b, d, abort);
        if (abort) return;
        if (b !== 1'b0) `uvm_error(get_name(), $sformatf("%s bus park cycle is not 0", who))
    endtask

    // follows one sequence after its SSC; abort = another SSC started inside it
    task collect(output bit abort);
        odve_rffe_item tr = odve_rffe_item::type_id::create("tr");
        bit [12:0]   v;
        bit [3:0]    drv;
        int unsigned per_cmd, per_dat;
        bit [7:0]    c;
        bit          perr, nrf;
        int          addr_cls;

        get_bits(13, v, drv, per_cmd, abort);
        if (abort) return;
        chk_master_frame("command frame", drv);
        tr.usid        = v[12:9];
        c              = v[8:1];
        tr.cmd_par_err = !(^v);
        if (!tr.decode(c)) begin
            `uvm_error(get_name(), $sformatf("unsupported command 0x%02h (usid %0h)", c, tr.usid))
            return;
        end
        if (tr.is_read() && tr.usid == 4'h0)
            `uvm_error(get_name(), $sformatf("%s addressed to the broadcast USID 0", tr.kind.name()))
        for (int i = 0; i < int'(tr.naddr()); i++) begin
            get_bits(9, v, drv, per_dat, abort);
            if (abort) return;
            chk_master_frame("address frame", drv);
            tr.addr = {tr.addr[7:0], v[8:1]};
            if (!(^v[8:0])) tr.addr_par_err = 1;
        end
        if (!tr.is_read()) begin
            if (tr.kind != ODVE_RFFE_REG0_WR) begin
                tr.data = new[tr.nbytes];
                for (int i = 0; i < int'(tr.nbytes); i++) begin
                    get_bits(9, v, drv, per_dat, abort);
                    if (abort) return;
                    chk_master_frame("write data frame", drv);
                    tr.data[i] = v[8:1];
                    if (!(^v[8:0]) && tr.data_par_err_idx < 0) tr.data_par_err_idx = i;
                end
            end
            get_bpc("master", abort);
            if (abort) return;
        end else begin
            get_bpc("master (read turnaround)", abort);
            if (abort) return;
            tr.data = new[tr.nbytes];
            for (int i = 0; i < int'(tr.nbytes); i++) begin
                get_bits(9, v, drv, per_dat, abort);
                if (abort) return;
                if (drv[0])
                    `uvm_error(get_name(), "the master drives SDATA during a read data frame")
                tr.data[i] = v[8:1];
                if (v[8:0] == 9'h0)    tr.nrf_mask[i] = 1'b1;
                else if (!(^v[8:0]))   `uvm_error(get_name(), $sformatf("read data frame %0d: parity error (0x%03h)", i, v[8:0]))
                if (per_dat > per_cmd) tr.half_speed = 1;
            end
            get_bpc("slave", abort);
            if (abort) return;
        end

        perr = tr.cmd_par_err || tr.addr_par_err || tr.data_par_err_idx >= 0;
        if (perr && cfg != null && cfg.chk_parity)
            `uvm_error(get_name(), {"parity error in a master frame: ", tr.convert2string()})
        n_seen++;
        `uvm_info(get_name(), tr.convert2string(), UVM_HIGH)
        nrf      = tr.nrf_mask != 0;
        addr_cls = (tr.addr < 16'h20) ? 0 : (tr.addr < 16'h40) ? 1 : 2;
        `odve_cov_sample(odve_rffe_cg, int'(tr.kind), int'(tr.nbytes), addr_cls, tr.usid == 4'h0, perr, nrf, tr.half_speed, tr.is_read())
        item_collected_port.write(tr);
    endtask

    virtual task run_phase(uvm_phase phase);
        bit abort;
        forever begin
            do sample(); while (!ssc_now);
            do begin
                collect(abort);
                if (abort) `uvm_error(get_name(), "SSC inside a command sequence: the sequence was aborted")
            end while (abort);
        end
    endtask
endclass
