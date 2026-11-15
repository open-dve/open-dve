// Passive observer of the SPI bus, cycle based: it samples every line at each
// posedge of the system clock (all agents and the RTL change them with
// non-blocking assignments on that clock, so a sclk half period must be at
// least 2 cycles). A frame opens when a chip select falls and closes when it
// rises; at every sampling edge of the selected slave's mode (cfg.dev[cs])
// one MOSI and one MISO bit are taken. The complete frame - words both ways,
// an incomplete last word, measured timing - goes out on
// item_collected_port and into the coverage.
//
// Protocol checks (uvm_error, id in brackets):
//   [SPI_MULTI_CS]  more than one chip select low at once
//   [SPI_CPOL]      sclk not at its idle level (cpol) when cs_n falls or rises
//   [SPI_LEAD]      cs_n fall -> first edge shorter than cfg.min_lead   (tL)
//   [SPI_TRAIL]     last edge -> cs_n rise shorter than cfg.min_trail  (tT)
//   [SPI_IDLE]      cs_n high time shorter than cfg.min_idle   (tI)
//   [SPI_MISO_CONT] more than one MISO driver enabled (once per episode)
//   [SPI_MISO_Z]    no MISO driver enabled at a sampling edge (once per frame)
// The tL/tT/tI limits default to one sclk half period (block guide fig. 4-2).
class odve_spi_mon extends uvm_monitor;
    `uvm_component_utils(odve_spi_mon)

    uvm_analysis_port #(odve_spi_item) item_collected_port;
    virtual odve_spi_if vif;
    odve_spi_cfg        cfg;
    int unsigned        n_seen = 0;
    int unsigned        n_err  = 0;

    `odve_cov_create(odve_spi_cg)

    function new(string name = "odve_spi_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
    endfunction

    function void proto_error(string id, string msg, odve_spi_item tr);
        n_err++;
        if (tr != null) tr.proto_err = 1;
        `uvm_error(id, msg)
    endfunction

    virtual task run_phase(uvm_phase phase);
        localparam int NCS = `ODVE_SPI_MAX_CS;
        odve_spi_item    tr;
        odve_spi_dev_cfg d;
        bit [NCS-1:0] cs_p = '1;
        bit           sclk_p;
        longint       cyc = 0;
        longint       t_rise[NCS];
        longint       t_fall, t_edge, t_wstart;
        int           act = -1;          // selected chip select, -1 = none
        int unsigned  nedge, bitc, interval;
        bit           cont_p = 0, z_seen;
        bit [31:0]    wo, wi;
        foreach (t_rise[i]) t_rise[i] = -1;

        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);
        sclk_p = vif.sclk;
        cs_p   = vif.cs_n;
        forever begin
            bit [NCS-1:0] cs;
            bit           sclk;
            @(posedge vif.clk);
            cyc++;
            cs   = vif.cs_n;
            sclk = vif.sclk;

            if ($countones(~cs) > 1 && $countones(~cs_p) <= 1)
                proto_error("SPI_MULTI_CS", $sformatf("cs_n=%b: more than one slave selected", cs), tr);
            if (vif.miso_ndrv > 1 && !cont_p)          // once per episode
                proto_error("SPI_MISO_CONT", $sformatf("%0d MISO drivers enabled at once", vif.miso_ndrv), tr);
            cont_p = (vif.miso_ndrv > 1);

            // inside a frame: sclk edges, then the close
            if (act >= 0) begin
                // an sclk edge inside the frame
                if (sclk != sclk_p) begin
                    bit leading = (sclk != d.cpol);
                    if (nedge == 0) begin
                        if (cyc - t_fall < cfg.min_t(cfg.min_lead))
                            proto_error("SPI_LEAD", $sformatf("cs%0d: first edge %0d cycle(s) after cs_n fell, min %0d (tL)", act, cyc - t_fall, cfg.min_t(cfg.min_lead)), tr);
                    end else if (nedge == 1) begin
                        interval = cyc - t_edge;
                        tr.half_period = interval;
                    end else if (bitc == 0 && leading && cyc - t_edge > interval) begin
                        tr.had_gap = 1;          // first edge of a word came late
                    end
                    if (leading ^ d.cpha) begin   // sampling edge
                        int unsigned pos = d.lsb_first ? bitc : d.word_bits - 1 - bitc;
                        if (vif.miso_ndrv == 0 && !z_seen) begin  // once per frame
                            z_seen = 1;
                            proto_error("SPI_MISO_Z", $sformatf("cs%0d: no MISO driver at bit %0d", act, bitc), tr);
                        end
                        wo[pos] = vif.mosi;
                        wi[pos] = vif.miso;
                        bitc++;
                        if (bitc == d.word_bits) begin
                            tr.mosi.push_back(wo);
                            tr.miso.push_back(wi);
                            bitc = 0; wo = '0; wi = '0;
                        end
                    end
                    nedge++;
                    t_edge = cyc;
                end
                // close the frame
                if (cs[act]) begin
                    if (sclk !== d.cpol)
                        proto_error("SPI_CPOL", $sformatf("cs%0d rose with sclk=%0b, %s", act, sclk, d.convert2string()), tr);
                    if (nedge > 0 && cyc - t_edge < cfg.min_t(cfg.min_trail))
                        proto_error("SPI_TRAIL", $sformatf("cs%0d rose %0d cycle(s) after the last edge, min %0d (tT)", act, cyc - t_edge, cfg.min_t(cfg.min_trail)), tr);
                    if (bitc != 0) begin
                        // keep the bits that arrived, right aligned in arrival order
                        tr.partial_bits = bitc;
                        tr.partial_mosi = d.lsb_first ? (wo & ((32'h1 << bitc) - 1)) : (wo >> (d.word_bits - bitc));
                    end
                    t_rise[act] = cyc;
                    n_seen++;
                    `uvm_info(get_name(), tr.convert2string(), UVM_HIGH)
                    `odve_cov_sample(odve_spi_cg, d.mode(), tr.word_bits, tr.lsb_first, tr.mosi.size(), act, tr.partial_bits != 0, tr.had_gap)
                    item_collected_port.write(tr);
                    act = -1;
                    tr  = null;
                end
            end
            // open a frame (also in the cycle another one closed)
            if (act < 0) begin
                for (int i = 0; i < NCS && act < 0; i++) begin
                    if (i < cfg.ncs && cs_p[i] && !cs[i]) begin
                        act = i;
                        d   = cfg.dev[i];
                        tr  = odve_spi_item::type_id::create("tr");
                        tr.cs = i;
                        tr.word_bits = d.word_bits;
                        tr.cpol = d.cpol; tr.cpha = d.cpha; tr.lsb_first = d.lsb_first;
                        t_fall = cyc; z_seen = 0; nedge = 0; bitc = 0; wo = '0; wi = '0; interval = 0;
                        if (sclk !== d.cpol)
                            proto_error("SPI_CPOL", $sformatf("cs%0d fell with sclk=%0b, %s", i, sclk, d.convert2string()), tr);
                        if (t_rise[i] >= 0 && cyc - t_rise[i] < cfg.min_t(cfg.min_idle))
                            proto_error("SPI_IDLE", $sformatf("cs%0d high for %0d cycle(s), min %0d (tI)", i, cyc - t_rise[i], cfg.min_t(cfg.min_idle)), tr);
                    end
                end
            end
            // a select that rose outside the active frame (e.g. a second one) still restarts its idle time
            for (int i = 0; i < NCS; i++) if (!cs_p[i] && cs[i]) t_rise[i] = cyc;
            cs_p   = cs;
            sclk_p = sclk;
        end
    endtask
endclass
