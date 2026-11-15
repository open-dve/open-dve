// SPMI slave driver: the same receiver as the RTL slave in vrf/dut
// (oversampled at the TB clock, SSC detection, odd parity on every frame),
// answering to cfg.sid. Registers 0..nregs-1 are read/write, register
// nregs (0x40) is the read-only power state (odve_spmi_pm_e) that Reset /
// Sleep / Shutdown / Wakeup set; Reset also clears the registers. Other
// addresses: writes ignored, reads answered with a No Response Frame.
//
// Error handling: a bad command frame and a bad address frame of a read end
// the sequence for the slave (no ACK, no data: the parked line reads 0); a
// bad address frame of a write drops the whole write, a bad data frame drops
// that frame and the ones after it (the ones before are written) - both
// answered with NACK. Everything else is answered with ACK.
// Two modes (cfg.slv_mode):
//
//   ODVE_SPMI_SLV_MEM  autonomous: registers and power state live here.
//   ODVE_SPMI_SLV_SEQ  reactive: each decoded request goes out on req_port
//                      (the slave sequencer's req_fifo) - a read once its
//                      address is known, a write once its data frames are
//                      in, a PM command once its command frame is - and the
//                      response item comes back from the responding
//                      sequence (seq/odve_spmi_slv_mem_seq.sv): read data +
//                      nrf_mask, or `ack` (ANDed with the parity verdict).
class odve_spmi_slv_drv extends uvm_driver #(odve_spmi_item);
    `uvm_component_utils(odve_spmi_slv_drv)

    typedef enum { S_IDLE, S_CMD, S_ADDR, S_WDATA, S_MBPC, S_RDATA, S_WBPC, S_ACK, S_SBPC } st_e;

    virtual odve_spmi_if vif;
    odve_spmi_cfg        cfg;
    uvm_analysis_port #(odve_spmi_item) req_port;

    bit [7:0]      mem [int unsigned];   // MEM mode
    odve_spmi_pm_e pm = ODVE_SPMI_ACTIVE;
    int unsigned   n_req = 0;

    st_e           st = S_IDLE;
    bit            sc, sd, sc_q, sd_q, armed, rise, fall;
    bit [12:0]     sh;
    int unsigned   bcnt, acnt, fidx, ngood;
    bit            drop, ack;
    bit [8:0]      rframe;
    odve_spmi_item cur, rsp;

    function new(string name = "odve_spmi_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
    endfunction

    // MEM mode: the response from the driver's own registers and power state
    function odve_spmi_item respond_from_mem(odve_spmi_item req);
        odve_spmi_item r = odve_spmi_item::type_id::create("rsp");
        r.ack = 1;
        case (req.kind)
            ODVE_SPMI_REG_RD, ODVE_SPMI_EXT_RD, ODVE_SPMI_EXTL_RD: begin
                r.data     = new[req.nbytes];
                r.nrf_mask = '0;
                for (int i = 0; i < int'(req.nbytes); i++) begin
                    int unsigned a = req.byte_addr(i);
                    if (a < cfg.nregs)       r.data[i] = mem.exists(a) ? mem[a] : 8'h00;
                    else if (a == cfg.nregs) r.data[i] = {6'h00, pm};
                    else                     r.nrf_mask[i] = 1'b1;
                end
            end
            ODVE_SPMI_REG0_WR: mem[0] = {1'b0, req.data[0][6:0]};
            ODVE_SPMI_RESET: begin
                mem.delete();
                pm = ODVE_SPMI_ACTIVE;
            end
            ODVE_SPMI_SLEEP:    pm = ODVE_SPMI_SLEEPING;
            ODVE_SPMI_SHUTDOWN: pm = ODVE_SPMI_SHUTDOWN_ST;
            ODVE_SPMI_WAKEUP:   pm = ODVE_SPMI_ACTIVE;
            default:
                foreach (req.data[i]) begin
                    int unsigned a = req.byte_addr(i);
                    if (a < cfg.nregs) mem[a] = req.data[i];
                end
        endcase
        return r;
    endfunction

    task handle(odve_spmi_item req);
        n_req++;
        `uvm_info(get_name(), {"request ", req.convert2string()}, UVM_HIGH)
        if (cfg.slv_mode == ODVE_SPMI_SLV_MEM) begin
            rsp = respond_from_mem(req);
        end else begin
            req_port.write(req);                // the responding sequence picks it up ...
            seq_item_port.get_next_item(rsp);   // ... and answers in zero time
            seq_item_port.item_done();
        end
    endtask

    function void drive(bit oe, bit o);
        vif.s_sdata_oe <= oe;
        vif.s_sdata_o  <= o;
    endfunction

    // command frame complete in sh
    task decode();
        bit [3:0] sa = sh[12:9];
        cur  = odve_spmi_item::type_id::create("req");
        st   = S_IDLE;
        drop  = 0;
        ack   = 1;
        ngood = 0;
        if (!(^sh)) return;                       // parity error: not for us
        if (!cur.decode(sh[8:1])) return;         // unsupported command
        cur.sid = sa;
        if (sa != cfg.sid) return;
        if (cur.kind == ODVE_SPMI_REG0_WR || cur.is_pm()) begin
            handle(cur);
            ack = rsp.ack;
            st  = S_WBPC;
            return;
        end
        acnt = cur.naddr();
        cur.data = new[0];
        if (acnt != 0)          st = S_ADDR;
        else if (cur.is_read()) begin st = S_MBPC; handle(cur); end
        else                    st = S_WDATA;
    endtask

    // a write's data frames are in (or its address was bad: drop)
    task end_write();
        bit [7:0] d[] = cur.data;
        st = S_WBPC;
        if (drop) ack = 0;
        if (ngood == 0 || cur.addr_par_err) return;
        cur.data   = new[ngood];
        foreach (cur.data[i]) cur.data[i] = d[i];
        cur.nbytes = ngood;
        handle(cur);
        ack = ack && rsp.ack;
    endtask

    task step();
        case (st)
            S_CMD: if (fall) begin
                sh = {sh[11:0], sd};
                if (++bcnt == 13) begin bcnt = 0; decode(); end
            end
            S_ADDR: if (fall) begin
                sh = {sh[11:0], sd};
                if (++bcnt == 9) begin
                    bcnt = 0;
                    if (!(^sh[8:0])) begin
                        if (cur.is_read()) st = S_IDLE;
                        else begin cur.addr_par_err = 1; drop = 1; end
                    end
                    cur.addr = {cur.addr[7:0], sh[8:1]};
                    if (st != S_IDLE && --acnt == 0) begin
                        if (cur.is_read()) begin st = S_MBPC; handle(cur); end
                        else begin st = S_WDATA; ngood = 0; end
                    end
                end
            end
            S_WDATA: if (fall) begin
                sh = {sh[11:0], sd};
                if (++bcnt == 9) begin
                    bcnt = 0;
                    if (!(^sh[8:0])) drop = 1;
                    if (!drop) begin
                        cur.data = new[fidx + 1](cur.data);
                        cur.data[fidx] = sh[8:1];
                        ngood = fidx + 1;
                    end
                    if (++fidx == cur.nbytes) end_write();
                end
            end
            S_MBPC: if (fall) begin           // the master's bus park ends: our turn
                st   = S_RDATA;
                bcnt = 0;
                fidx = 0;
            end
            S_RDATA: if (rise) begin
                if (bcnt == 0) rframe = rsp.nrf_mask[fidx] ? 9'h000 : {rsp.data[fidx], ~^rsp.data[fidx]};
                drive(1'b1, rframe[8 - bcnt]);
                if (++bcnt == 9) begin
                    bcnt = 0;
                    if (++fidx == cur.nbytes) st = S_SBPC;
                end
            end
            S_WBPC: if (fall) st = S_ACK;     // the master's bus park ends: ACK/NACK
            S_ACK: if (rise) begin
                drive(1'b1, ack);
                st   = S_SBPC;
                bcnt = 0;
            end
            S_SBPC: begin
                if (rise) begin drive(1'b1, 1'b0); bcnt = 1; end
                else if (fall && bcnt == 1) begin drive(1'b0, 1'b0); st = S_IDLE; end
            end
            default: ;
        endcase
    endtask

    virtual task run_phase(uvm_phase phase);
        drive(1'b0, 1'b0);
        forever begin
            @(posedge vif.clk);
            if (vif.rst_n !== 1'b1) begin
                st = S_IDLE; armed = 0; sc_q = 0; sd_q = 0;
                continue;
            end
            sc   = (vif.sclk === 1'b1);
            sd   = (vif.sdata === 1'b1);
            rise = sc && !sc_q;
            fall = !sc && sc_q;
            if (rise) armed = 0;
            else if (!sc && !sc_q && sd && !sd_q) armed = 1;
            else if (!sc && !sc_q && !sd && sd_q && armed) begin   // SSC: (re)start
                armed = 0;
                st    = S_CMD;
                bcnt  = 0;
                fidx  = 0;
                sh    = '0;
                drive(1'b0, 1'b0);
            end
            sc_q = sc;
            sd_q = sd;
            step();
        end
    endtask
endclass
