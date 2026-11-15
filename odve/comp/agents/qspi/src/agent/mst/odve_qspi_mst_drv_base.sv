// QSPI master (flash controller side): owns cs_n and sclk, drives io through
// m_io/m_io_oe only in the phases that are its own (instruction, address,
// mode bits, write data) and releases the lines for dummy clocks and read
// data. Cycle based: edges are non-blocking assignments at posedge clk.
// Data goes out on falling sclk edges and is sampled on rising ones (SPI
// mode 0 and 3 both; cfg.bus.cpol only moves the idle level - in mode 0 the
// first bit is put out with cs_n, in mode 3 on the first, falling, edge).
// The frame's shape comes from odve_qspi_fmt(cmd, cfg.bus.qpi).
class odve_qspi_mst_drv_base extends uvm_driver #(odve_qspi_item);
    `uvm_component_utils(odve_qspi_mst_drv_base)

    virtual odve_qspi_if vif;
    odve_qspi_cfg        cfg;
    time                 tclk, last_rise;

    function new(string name = "odve_qspi_mst_drv_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task wait_cycles(int unsigned n);
        repeat (n) @(posedge vif.clk);
    endtask

    virtual task run_phase(uvm_phase phase);
        vif.sclk    <= cfg.bus.cpol;
        vif.cs_n    <= 1'b1;
        vif.m_io    <= '1;
        vif.m_io_oe <= '0;
        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);
        tclk = $time;
        @(posedge vif.clk);
        tclk = $time - tclk;
        last_rise = 0;
        forever begin
            seq_item_port.get_next_item(req);
            drive_frame(req);
            seq_item_port.item_done();
        end
    endtask

    static function bit [3:0] lane_mask(int unsigned lanes);
        return (lanes == 4) ? 4'hF : (lanes == 2) ? 4'h3 : 4'h1;
    endfunction

    // value of `lanes` lanes at clock j of byte b (MSB first)
    static function bit [3:0] lane_val(bit [7:0] b, int unsigned j, int unsigned lanes);
        bit [7:0] s = b << (j * lanes);
        return (lanes == 4) ? s[7:4] : (lanes == 2) ? {2'b0, s[7:6]} : {3'b0, s[7]};
    endfunction

    virtual task drive_frame(odve_qspi_item tr);
        odve_qspi_fmt_t f;
        bit [3:0]    oe[$], v[$];        // per clock: master lanes and values
        bit          smp[$];             // per clock: sample slave data
        int unsigned H     = cfg.half_period;
        int unsigned lead  = (tr.lead  >= 0) ? tr.lead  : cfg.lead;
        int unsigned trail = (tr.trail >= 0) ? tr.trail : cfg.trail;
        int unsigned idle  = (tr.idle  >= 0) ? tr.idle  : cfg.idle;
        int unsigned N, cpb;
        bit [7:0]    sh;
        int unsigned shn;

        tr.qpi = cfg.bus.qpi;
        f = odve_qspi_fmt(tr.cmd, tr.qpi, cfg.bus.qpi_dummy);
        tr.rdata.delete();
        // instruction
        cpb = 8 / f.cmd_lanes;
        for (int j = 0; j < cpb; j++) begin oe.push_back(lane_mask(f.cmd_lanes)); v.push_back(lane_val(tr.cmd, j, f.cmd_lanes)); smp.push_back(0); end
        if (f.valid) begin
            // address, mode bits, dummy
            if (f.addr_lanes) begin
                bit [23:0] a = tr.addr;
                for (int j = 0; j < 24 / f.addr_lanes; j++) begin
                    oe.push_back(lane_mask(f.addr_lanes));
                    v.push_back(lane_val(a[23:16], 0, f.addr_lanes));
                    a = a << f.addr_lanes;
                    smp.push_back(0);
                end
            end
            for (int j = 0; j < f.mode_clks; j++) begin oe.push_back(lane_mask(f.addr_lanes)); v.push_back(lane_val(tr.mode_byte, j, f.addr_lanes)); smp.push_back(0); end
            for (int j = 0; j < f.dummy_clks; j++) begin oe.push_back(4'h0); v.push_back(4'hF); smp.push_back(0); end
            // data
            if (f.data_lanes) begin
                cpb = 8 / f.data_lanes;
                if (f.data_out)
                    repeat (tr.nrd * cpb) begin oe.push_back(4'h0); v.push_back(4'hF); smp.push_back(1); end
                else
                    foreach (tr.wdata[i])
                        for (int j = 0; j < cpb; j++) begin oe.push_back(lane_mask(f.data_lanes)); v.push_back(lane_val(tr.wdata[i], j, f.data_lanes)); smp.push_back(0); end
            end
        end
        repeat (tr.extra_clks) begin oe.push_back(4'h0); v.push_back(4'hF); smp.push_back(0); end
        N = oe.size();
        if (tr.abort_after_clks >= 0 && tr.abort_after_clks < N) N = tr.abort_after_clks;

        // tSHSL since the last frame, sclk at its idle level
        if (vif.sclk !== cfg.bus.cpol) begin vif.sclk <= cfg.bus.cpol; wait_cycles(idle); end
        while ($time - last_rise < idle * tclk) @(posedge vif.clk);
        vif.cs_n <= 1'b0;
        if (!cfg.bus.cpol && N > 0) begin vif.m_io <= v[0]; vif.m_io_oe <= oe[0]; end
        wait_cycles(lead);
        sh = '0; shn = 0;
        for (int k = 0; k < N; k++) begin
            if (cfg.bus.cpol) begin                      // mode 3: falling edge first, puts clock k's bits out
                vif.sclk    <= 1'b0;
                vif.m_io    <= v[k];
                vif.m_io_oe <= oe[k];
                wait_cycles(H);
            end
            vif.sclk <= 1'b1;                        // rising: both sides sample
            if (smp[k]) begin
                bit [3:0] io = vif.io;
                sh  = (sh << f.data_lanes) | 8'((f.data_lanes == 1) ? {3'b0, io[1]} : (f.data_lanes == 2) ? {2'b0, io[1:0]} : io);
                shn += f.data_lanes;
                if (shn == 8) begin tr.rdata.push_back(sh); sh = '0; shn = 0; end
            end
            if (!cfg.bus.cpol) begin                     // mode 0: falling edge after, puts clock k+1's bits out
                wait_cycles(H);
                vif.sclk    <= 1'b0;
                vif.m_io    <= (k + 1 < N) ? v[k + 1] : 4'hF;
                vif.m_io_oe <= (k + 1 < N) ? oe[k + 1] : 4'h0;
            end
            if (k + 1 < N) wait_cycles(H);
        end
        if (tr.cpol_err) begin wait_cycles(H); vif.sclk <= ~cfg.bus.cpol; end
        wait_cycles(trail);
        vif.cs_n    <= 1'b1;
        vif.m_io_oe <= 4'h0;
        last_rise = $time;
        wait_cycles(1);                              // nothing else moves in the cycle cs_n rises
        if (tr.cpol_err) begin wait_cycles(H); vif.sclk <= cfg.bus.cpol; wait_cycles(H); end
    endtask
endclass
