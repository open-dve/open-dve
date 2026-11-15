// Passive observer of the QSPI bus, cycle based: samples every line at each
// posedge of the system clock and reconstructs each frame (cs_n low ... high)
// from its rising sclk edges with odve_qspi_decoder, in the mode the bus is
// in (cfg.bus.qpi, cfg.bus.cpol). The frame goes out on item_collected_port and into
// the coverage.
//
// Protocol checks (uvm_error, id in brackets; QSPI_UNK is a warning):
//   [QSPI_CPOL]    sclk not at its idle level (cpol) when cs_n falls or rises
//   [QSPI_LEAD]    cs_n fall -> first sclk edge shorter than min_lead     (tSLCH)
//   [QSPI_TRAIL]   last sclk edge -> cs_n rise shorter than min_trail     (tCHSH)
//   [QSPI_IDLE]    cs_n high shorter than min_idle                        (tSHSL)
//   [QSPI_IO_CONT] two drivers enabled on one io line (once per episode)
//   [QSPI_IO_Z]    a lane the current phase needs is not driven (cfg.chk_undriven; once per frame)
//   [QSPI_TRUNC]   cs_n rose inside the instruction/address/dummy phase or mid data byte
//   [QSPI_EXTRA]   clocks after a command that has no data phase
//   [QSPI_UNK]     opcode not defined in this mode (warning)
class odve_qspi_mon extends uvm_monitor;
    `uvm_component_utils(odve_qspi_mon)

    uvm_analysis_port #(odve_qspi_item) item_collected_port;
    virtual odve_qspi_if vif;
    odve_qspi_cfg        cfg;
    odve_qspi_decoder    dec;
    int unsigned         n_seen = 0;
    bit                  act = 0;      // inside a frame

    `odve_cov_create(odve_qspi_cg)

    function new(string name = "odve_qspi_mon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        item_collected_port = new("item_collected_port", this);
        dec = odve_qspi_decoder::type_id::create("dec");
    endfunction

    function void proto_error(string id, string msg);
        if (act && dec.tr != null) dec.tr.proto_err = 1;
        `uvm_error(id, msg)
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit      cs_p, sclk_p, cont_p = 0, z_seen;
        longint  cyc = 0, t_fall, t_edge, t_rise = -1;
        int unsigned nedge;

        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);
        cs_p = vif.cs_n; sclk_p = vif.sclk;
        forever begin
            bit       cs, sclk, cont;
            bit [3:0] io;
            @(posedge vif.clk);
            cyc++;
            cs = vif.cs_n; sclk = vif.sclk; io = vif.io;

            cont = 0;
            for (int i = 0; i < 4; i++) if (vif.io_ndrv[i] > 1) cont = 1;
            if (cont && !cont_p) proto_error("QSPI_IO_CONT", $sformatf("io: two drivers on one line (ndrv %0d %0d %0d %0d)", vif.io_ndrv[3], vif.io_ndrv[2], vif.io_ndrv[1], vif.io_ndrv[0]));
            cont_p = cont;

            if (act) begin
                if (sclk != sclk_p) begin
                    if (nedge == 0 && cyc - t_fall < cfg.min_t(cfg.min_lead))
                        proto_error("QSPI_LEAD", $sformatf("first sclk edge %0d cycle(s) after cs_n fell, min %0d", cyc - t_fall, cfg.min_t(cfg.min_lead)));
                    if (sclk) begin                               // rising: sample
                        int unsigned k = dec.rcnt;
                        bit [3:0] need = dec.master_lanes(k) | dec.slave_lanes(k);
                        if (cfg.chk_undriven && !z_seen) begin
                            for (int i = 0; i < 4; i++)
                                if (need[i] && vif.io_ndrv[i] == 0 && !z_seen) begin
                                    z_seen = 1;
                                    proto_error("QSPI_IO_Z", $sformatf("clock %0d (%s) of %02h: io%0d not driven", k, dec.phase(k).name(), dec.tr.cmd, i));
                                end
                        end
                        dec.rise(io);
                        if (dec.rcnt == dec.cmd_clks && dec.tr.unknown)
                            `uvm_warning("QSPI_UNK", $sformatf("opcode %02h is not defined in %s mode", dec.tr.cmd, dec.tr.qpi ? "QPI" : "SPI"))
                    end
                    nedge++;
                    t_edge = cyc;
                end
                if (cs) begin                                     // close
                    odve_qspi_item tr;
                    if (sclk !== cfg.bus.cpol) proto_error("QSPI_CPOL", $sformatf("cs_n rose with sclk=%0b (mode %0d)", sclk, cfg.bus.cpol ? 3 : 0));
                    if (nedge > 0 && cyc - t_edge < cfg.min_t(cfg.min_trail))
                        proto_error("QSPI_TRAIL", $sformatf("cs_n rose %0d cycle(s) after the last edge, min %0d", cyc - t_edge, cfg.min_t(cfg.min_trail)));
                    tr = dec.finish();
                    if (!tr.unknown) begin
                        if (tr.truncated)
                            proto_error("QSPI_TRUNC", $sformatf("%02h: cs_n rose after %0d of %0d header clocks", tr.cmd, tr.nclk, dec.hdr));
                        else if (tr.partial_bits)
                            proto_error("QSPI_TRUNC", $sformatf("%02h: cs_n rose %0d bit(s) into a data byte", tr.cmd, tr.partial_bits));
                        else if (dec.f.data_lanes == 0 && tr.nclk > dec.hdr)
                            proto_error("QSPI_EXTRA", $sformatf("%02h: %0d clock(s) after a command without data", tr.cmd, tr.nclk - dec.hdr));
                    end
                    n_seen++;
                    `uvm_info(get_name(), tr.convert2string(), UVM_HIGH)
                    `odve_cov_sample(odve_qspi_cg, tr.cmd, dec.f.fmt_code, tr.qpi, tr.wdata.size() + tr.rdata.size(), (tr.truncated || tr.partial_bits) ? 1 : 0, cfg.bus.cpol)
                    item_collected_port.write(tr);
                    act = 0;
                    t_rise = cyc;
                end
            end
            if (!act && cs_p && !cs) begin                        // open
                act = 1; nedge = 0; z_seen = 0; t_fall = cyc;
                dec.start(cfg.bus.qpi, cfg.bus.qpi_dummy);
                if (sclk !== cfg.bus.cpol) proto_error("QSPI_CPOL", $sformatf("cs_n fell with sclk=%0b (mode %0d)", sclk, cfg.bus.cpol ? 3 : 0));
                if (t_rise >= 0 && cyc - t_rise < cfg.min_t(cfg.min_idle))
                    proto_error("QSPI_IDLE", $sformatf("cs_n high for %0d cycle(s), min %0d", cyc - t_rise, cfg.min_t(cfg.min_idle)));
            end
            cs_p = cs; sclk_p = sclk;
        end
    endtask
endclass
