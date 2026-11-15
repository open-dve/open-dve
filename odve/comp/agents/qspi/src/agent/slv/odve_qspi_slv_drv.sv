// QSPI slave driver: a behavioural serial NOR flash on the bus. Cycle based
// like the monitor: decodes each frame from the rising sclk edges
// (odve_qspi_decoder, in mode cfg.bus.qpi) and, for an accepted read-type
// command, drives the data lanes (s_io/s_io_oe) from the falling edge that
// starts the data phase, one cycle after the edge. Where the answers come
// from, per cfg.slv_mode:
//   ODVE_QSPI_SLV_MEM  autonomous: odve_qspi_flash_model inside the driver;
//   ODVE_QSPI_SLV_SEQ  reactive: requests on req_port (the slave sequencer's
//                      req_fifo) - REQ_DECODE when the opcode is in (answer:
//                      ack = accepted), REQ_BYTE for every data byte to send
//                      (answer: rdata[0]), REQ_END at cs_n rise with the
//                      whole frame - answered by odve_qspi_slv_rsp_seq,
//                      which holds the model.
class odve_qspi_slv_drv extends uvm_driver #(odve_qspi_item);
    `uvm_component_utils(odve_qspi_slv_drv)

    virtual odve_qspi_if  vif;
    odve_qspi_cfg         cfg;
    uvm_analysis_port #(odve_qspi_item) req_port;
    odve_qspi_flash_model model;          // MEM mode
    odve_qspi_decoder     dec;
    longint               cyc = 0;        // system clock cycles (busy timing)
    int unsigned          n_frames = 0;

    function new(string name = "odve_qspi_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
        model = odve_qspi_flash_model::type_id::create("model");
        dec   = odve_qspi_decoder::type_id::create("dec");
    endfunction

    virtual function void start_of_simulation_phase(uvm_phase phase);
        model.cfg = cfg;
    endfunction

    task ask(odve_qspi_slv_req_e kind, odve_qspi_item tr, output odve_qspi_item rsp);
        tr.slv_req = kind;
        tr.t_cyc   = cyc;
        req_port.write(tr);
        seq_item_port.get_next_item(rsp);
        seq_item_port.item_done();
    endtask

    function odve_qspi_item req_of(odve_qspi_item src, int unsigned idx);
        odve_qspi_item r = odve_qspi_item::type_id::create("req");
        r.cmd = src.cmd; r.qpi = src.qpi; r.addr = src.addr; r.idx = idx;
        return r;
    endfunction

    task decide(odve_qspi_item tr, output bit acc);
        odve_qspi_item rsp;
        if (cfg.slv_mode == ODVE_QSPI_SLV_MEM) acc = model.accepts(tr.cmd, tr.qpi, cyc);
        else begin ask(ODVE_QSPI_REQ_DECODE, req_of(tr, 0), rsp); acc = rsp.ack; end
    endtask

    task get_byte(odve_qspi_item tr, int unsigned i, output bit [7:0] b);
        odve_qspi_item rsp;
        if (cfg.slv_mode == ODVE_QSPI_SLV_MEM) b = model.out_byte(tr.cmd, tr.qpi, tr.addr, i, cyc);
        else begin ask(ODVE_QSPI_REQ_BYTE, req_of(tr, i), rsp); b = rsp.rdata[0]; end
    endtask

    task tick();
        @(posedge vif.clk);
        cyc++;
    endtask

    virtual task run_phase(uvm_phase phase);
        vif.s_io    <= '1;
        vif.s_io_oe <= '0;
        wait (vif.rst_n === 1'b1);
        forever begin
            bit          acc, decided, sclk_p;
            bit [7:0]    ob;
            odve_qspi_item tr, rsp;
            do tick(); while (vif.cs_n !== 1'b0);
            dec.start(cfg.bus.qpi, cfg.bus.qpi_dummy);
            acc = 0; decided = 0;
            sclk_p = vif.sclk;
            forever begin
                tick();
                if (vif.cs_n !== 1'b0) break;
                if (vif.sclk !== sclk_p) begin
                    if (vif.sclk) begin                         // rising: sample
                        dec.rise(vif.io);
                        if (!decided && dec.rcnt == dec.cmd_clks) begin
                            decided = 1;
                            if (dec.known) decide(dec.tr, acc);
                        end
                    end else if (acc && dec.f.data_out && dec.rcnt >= dec.hdr) begin   // falling: data out for clock rcnt
                        int unsigned k   = dec.rcnt - dec.hdr;
                        int unsigned dl  = dec.f.data_lanes;
                        int unsigned cpb = 8 / dl;
                        bit [7:0]    s;
                        if (k % cpb == 0) get_byte(dec.tr, k / cpb, ob);
                        s = ob << ((k % cpb) * dl);
                        vif.s_io    <= (dl == 4) ? s[7:4] : (dl == 2) ? {2'b11, s[7:6]} : {2'b11, s[7], 1'b1};
                        vif.s_io_oe <= (dl == 4) ? 4'hF : (dl == 2) ? 4'h3 : 4'h2;
                    end
                    sclk_p = vif.sclk;
                end
            end
            vif.s_io_oe <= '0;
            tr = dec.finish();
            if (cfg.slv_mode == ODVE_QSPI_SLV_MEM) model.end_frame(tr, acc, cyc);
            else begin
                tr.ack = acc;
                ask(ODVE_QSPI_REQ_END, tr, rsp);
            end
            n_frames++;
        end
    endtask
endclass
