// SPI master: owns sclk, mosi and the chip selects. Cycle based on the
// system clock: every edge it makes is a non-blocking assignment at a
// posedge, MISO is read at the posedge of the sampling sclk edge (the value
// the slave has had for a whole half period).
//
// Per item (block guide 4.4, figures 4-2/4-3):
//   sclk to the slave's cpol (waiting tI if it had to change), cs_n low,
//   CPHA=0: first MOSI bit with cs_n, then per bit leading edge = sample,
//           trailing edge = shift the next bit out;
//   CPHA=1: per bit leading edge = shift out, trailing edge = sample;
//   words back to back under one cs_n (word_gap extra idle cycles between
//   them), tT after the last edge cs_n high, tI before the next frame.
// abort_after_bits / lead / trail / idle / cpol_err on the item inject violations.
class odve_spi_mst_drv_base extends uvm_driver #(odve_spi_item);
    `uvm_component_utils(odve_spi_mst_drv_base)

    virtual odve_spi_if vif;
    odve_spi_cfg        cfg;
    time                tclk;                             // system clock period, measured
    time                last_rise[`ODVE_SPI_MAX_CS];      // when each cs_n last rose
    time                bus_rise;                         // when any cs_n last rose

    function new(string name = "odve_spi_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task wait_cycles(int unsigned n);
        repeat (n) @(posedge vif.clk);
    endtask

    virtual task run_phase(uvm_phase phase);
        vif.sclk <= cfg.dev[0].cpol;
        vif.mosi <= 1'b0;
        vif.cs_n <= '1;
        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);
        tclk = $time;
        @(posedge vif.clk);
        tclk = $time - tclk;
        foreach (last_rise[i]) last_rise[i] = 0;
        bus_rise = 0;
        forever begin
            seq_item_port.get_next_item(req);
            drive_frame(req);
            seq_item_port.item_done();
        end
    endtask

    function bit bit_of(bit [31:0] w, int unsigned i, odve_spi_dev_cfg d);
        return d.lsb_first ? w[i] : w[d.word_bits - 1 - i];
    endfunction

    virtual task drive_frame(odve_spi_item tr);
        odve_spi_dev_cfg d = cfg.dev[tr.cs];
        int unsigned H     = cfg.half_period;
        int unsigned lead  = (tr.lead  >= 0) ? tr.lead  : cfg.lead;
        int unsigned trail = (tr.trail >= 0) ? tr.trail : cfg.trail;
        int unsigned idle  = (tr.idle  >= 0) ? tr.idle  : cfg.idle;
        int unsigned nbits = 0;
        int unsigned total = tr.mosi.size() * d.word_bits;
        bit [31:0]   wi;
        bit          stop = 0;

        tr.word_bits = d.word_bits;
        tr.cpol = d.cpol; tr.cpha = d.cpha; tr.lsb_first = d.lsb_first;
        tr.miso.delete();
        if (tr.abort_after_bits >= 0 && tr.abort_after_bits < total) total = tr.abort_after_bits;

        if (vif.sclk !== d.cpol) begin            // mode change: settle sclk while deselected
            vif.sclk <= d.cpol;
            wait_cycles(cfg.idle);
        end
        // tI: cs_n high for `idle` cycles before it falls again; and at least
        // one cycle between any select rising and the next one falling
        while ($time - last_rise[tr.cs] < idle * tclk || $time - bus_rise < tclk) @(posedge vif.clk);
        vif.cs_n[tr.cs] <= 1'b0;
        if (!d.cpha && total > 0) vif.mosi <= bit_of(tr.mosi[0], 0, d);
        wait_cycles(lead);

        foreach (tr.mosi[w]) begin
            wi = '0;
            for (int unsigned b = 0; b < d.word_bits; b++) begin
                if (nbits == total) begin stop = 1; break; end
                // leading edge
                vif.sclk <= ~d.cpol;
                if (d.cpha) vif.mosi <= bit_of(tr.mosi[w], b, d);
                else        wi[d.lsb_first ? b : d.word_bits - 1 - b] = vif.miso;
                wait_cycles(H);
                // trailing edge
                vif.sclk <= d.cpol;
                if (d.cpha) wi[d.lsb_first ? b : d.word_bits - 1 - b] = vif.miso;
                else if (b + 1 < d.word_bits)    vif.mosi <= bit_of(tr.mosi[w], b + 1, d);
                else if (w + 1 < tr.mosi.size()) vif.mosi <= bit_of(tr.mosi[w + 1], 0, d);
                nbits++;
                if (nbits < total) begin
                    wait_cycles(H);
                    if (b + 1 == d.word_bits) wait_cycles(tr.word_gap);
                end
            end
            if (stop) break;
            tr.miso.push_back(wi);
        end
        if (tr.cpol_err) begin                     // inject: leave sclk off idle at cs_n rise
            wait_cycles(H);
            vif.sclk <= ~d.cpol;
        end
        wait_cycles(trail);
        vif.cs_n[tr.cs] <= 1'b1;
        last_rise[tr.cs] = $time;
        bus_rise = $time;
        wait_cycles(1);                            // nothing else moves in the cycle cs_n rises
        if (tr.cpol_err) begin
            wait_cycles(H);
            vif.sclk <= d.cpol;
            wait_cycles(H);
        end
    endtask
endclass
