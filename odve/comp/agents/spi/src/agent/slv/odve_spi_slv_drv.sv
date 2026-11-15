// SPI slave driver: answers chip select cfg.slv_cs through s_miso /
// s_miso_oe[cfg.slv_cs] (enabled only while selected, the explicit form of a
// tristate MISO). Cycle based like the monitor: lines are sampled at each
// posedge of the system clock, so a MISO bit appears one cycle after the
// shifting sclk edge (or after cs_n fell, for CPHA=0's first bit).
//
// What it sends comes from a word source, per cfg.slv_mode:
//   ODVE_SPI_SLV_MEM  autonomous: an odve_spi_slv_model inside the driver
//                     (cfg.slv_id, cfg.slv_nbytes) - no sequencer needed;
//   ODVE_SPI_SLV_SEQ  reactive: at cs_n fall, after every complete word and
//                     at cs_n rise the driver publishes a request on req_port
//                     (the slave sequencer's req_fifo) carrying the words
//                     received so far; the responding sequence answers with
//                     the next word to send in rsp.miso[0]
//                     (seq/odve_spi_slv_rsp_seq.sv, or one of your own).
class odve_spi_slv_drv extends uvm_driver #(odve_spi_item);
    `uvm_component_utils(odve_spi_slv_drv)

    virtual odve_spi_if vif;
    odve_spi_cfg        cfg;
    uvm_analysis_port #(odve_spi_item) req_port;
    odve_spi_slv_model  model;          // MEM mode
    int unsigned        n_frames = 0;

    function new(string name = "odve_spi_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
        model = odve_spi_slv_model::type_id::create("model");
    endfunction

    virtual function void start_of_simulation_phase(uvm_phase phase);
        model.id     = cfg.slv_id;
        model.nbytes = cfg.slv_nbytes;
    endfunction

    // The word to send as word n; rx = the words received so far, last = frame over.
    task next_word(int unsigned n, bit [31:0] rx[$], bit last, odve_spi_dev_cfg d, output bit [31:0] w);
        if (cfg.slv_mode == ODVE_SPI_SLV_MEM) begin
            while (model.nrx < rx.size()) model.rx_word(rx[model.nrx], d.word_bits);
            w = last ? '0 : model.tx_word(n, d.word_bits);
        end else begin
            odve_spi_item req = odve_spi_item::type_id::create("req");
            odve_spi_item rsp;
            req.cs = cfg.slv_cs;
            req.word_bits = d.word_bits;
            req.cpol = d.cpol; req.cpha = d.cpha; req.lsb_first = d.lsb_first;
            req.mosi = rx;
            req.frame_end = last;
            req_port.write(req);
            seq_item_port.get_next_item(rsp);
            w = (rsp.miso.size() > 0) ? rsp.miso[0] : '0;
            seq_item_port.item_done();
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        int unsigned c = cfg.slv_cs;
        vif.s_miso[c]    <= 1'b1;
        vif.s_miso_oe[c] <= 1'b0;
        wait (vif.rst_n === 1'b1);
        forever begin
            odve_spi_dev_cfg d;
            bit [31:0]   rx[$];
            bit [31:0]   tx, wo;
            int unsigned bitc;
            bit          sclk_p;
            // wait for our select
            do @(posedge vif.clk); while (vif.cs_n[c] !== 1'b0);
            d = cfg.dev[c];
            if (cfg.slv_mode == ODVE_SPI_SLV_MEM) model.start_frame();
            rx.delete();
            bitc = 0; wo = '0;
            sclk_p = vif.sclk;
            next_word(0, rx, 0, d, tx);
            vif.s_miso_oe[c] <= 1'b1;
            if (!d.cpha) vif.s_miso[c] <= d.lsb_first ? tx[0] : tx[d.word_bits - 1];
            forever begin
                @(posedge vif.clk);
                if (vif.cs_n[c] !== 1'b0) break;
                if (vif.sclk !== sclk_p) begin
                    bit leading = (vif.sclk != d.cpol);
                    if (leading ^ d.cpha) begin                  // sample
                        wo[d.lsb_first ? bitc : d.word_bits - 1 - bitc] = vif.mosi;
                        bitc++;
                        if (bitc == d.word_bits) begin
                            rx.push_back(wo);
                            next_word(rx.size(), rx, 0, d, tx);
                            bitc = 0; wo = '0;
                        end
                    end else begin                                // shift: bit bitc of the current word
                        vif.s_miso[c] <= d.lsb_first ? tx[bitc] : tx[d.word_bits - 1 - bitc];
                    end
                    sclk_p = vif.sclk;
                end
            end
            vif.s_miso_oe[c] <= 1'b0;
            next_word(rx.size() + 1, rx, 1, d, tx);           // frame over: last writes, no data
            n_frames++;
        end
    endtask
endclass
