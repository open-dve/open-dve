// I3C SDR target. The same state machine as the RTL target in vrf/dut
// (cycle for cycle: one step per clk, on values sampled at the preceding
// negedge), driving SDA through t_sda_oe/t_sda_o/t_sda_pp:
//
//   - answers 7E/W (CCC follows), ENTDAA (48-bit PID + BCR + DCR, open-drain,
//     arbitrated bit by bit; address parity checked, NACK on a bad one),
//     RSTDAA, SETDASA (cfg.static_addr), ENEC/DISEC, SETMWL/GETMWL, GETPID,
//     GETBCR, GETDCR, GETSTATUS (bit 5 protocol error, bit 0 IBI pending)
//   - private write/read at its dynamic address; T-bit parity checked on
//     writes (error -> status bit, rest of the transfer ignored); reads end
//     with T=0 on the last register, otherwise the controller decides
//   - In-Band Interrupt: request_ibi(mdb) - START request on an idle bus or
//     arbitration in the header after any START; MDB sent when BCR[2]
//   - Hot-Join: request_hj() while it has no dynamic address (7'h02/W);
//     a NACKed Hot-Join is dropped, a NACKed IBI stays pending
//
// Where the private-transfer bytes come from (cfg.slv_mode):
//   ODVE_I3C_SLV_MEM  autonomous: cfg.nregs registers and the pointer live here
//   ODVE_I3C_SLV_SEQ  reactive: each private byte is published on req_port
//                     (kind PRIV_WR with data[0] and byte index len, or
//                     PRIV_RD) and answered by the responding sequence
//                     (seq/odve_i3c_slv_mem_seq.sv): data[0] and t_end (last)
class odve_i3c_slv_drv extends uvm_driver #(odve_i3c_item);
    `uvm_component_utils(odve_i3c_slv_drv)

    virtual odve_i3c_if vif;
    odve_i3c_cfg        cfg;
    uvm_analysis_port #(odve_i3c_item) req_port;

    typedef enum int { S_IDLE, S_HDR, S_ACK, S_IBIACK, S_CCC, S_WR, S_RD,
                       S_DAAID, S_DAAADR, S_DAAACK, S_IGN } st_e;
    typedef enum int { CTX_NONE, CTX_BC, CTX_DIR } ctx_e;

    // target state, visible to tests
    bit          has_da;
    bit [6:0]    da;
    bit          enint = 1, enhj = 1;
    bit [15:0]   mwl   = 16'h0010;
    bit          perr;
    bit          ibi_pending;
    bit [7:0]    mdb;
    bit          hj_pending;
    bit [7:0]    regs [];
    int unsigned ptr;

    // state machine
    st_e         st = S_IDLE, nxt = S_IDLE;
    ctx_e        ctx = CTX_NONE;
    int unsigned bcnt, nbyte, idle_cnt;
    bit [7:0]    sr, ccc, tx;
    bit          arb, arb_hj, req_drv, is_ccc, ibi_tx, entdaa, tx_last;
    bit [6:0]    new_da;
    bit          scl_q = 1, sda_q = 1;
    bit          s_scl, s_sda;

    function new(string name = "odve_i3c_slv_drv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req_port = new("req_port", this);
    endfunction

    // ---- API for tests
    function void request_ibi(bit [7:0] m);
        ibi_pending = 1;
        mdb         = m;
    endfunction
    function void request_hj();
        hj_pending = 1;
    endfunction

    function bit [63:0] daa_id();
        return {cfg.pid, cfg.bcr, cfg.dcr};
    endfunction
    function bit [7:0] my_hdr();
        return arb_hj ? {I3C_HJ_ADDR, 1'b0} : {da, 1'b1};
    endfunction
    function bit ibi_ok();
        return ibi_pending && enint && has_da && cfg.bcr[1];
    endfunction
    function bit hj_ok();
        return hj_pending && !has_da && enhj;
    endfunction
    function bit dir_ok(bit [7:0] c, bit rnw);
        case (c)
            I3C_CCC_ENEC_D, I3C_CCC_DISEC_D, I3C_CCC_SETMWL_D:                      return !rnw;
            I3C_CCC_GETMWL, I3C_CCC_GETPID, I3C_CCC_GETBCR, I3C_CCC_GETDCR, I3C_CCC_GETSTATUS: return rnw;
            default:                                                               return 0;
        endcase
    endfunction

    // the byte to send next and whether it is the last one
    task rd_next(output bit [7:0] v, output bit last);
        v    = 8'h00;
        last = 1;
        if (ibi_tx) begin
            v = mdb;
        end else if (!is_ccc) begin
            if (cfg.slv_mode == ODVE_I3C_SLV_SEQ) begin
                odve_i3c_item rq = odve_i3c_item::type_id::create("rq"), rsp;
                rq.kind = I3C_PRIV_RD;
                rq.addr = da;
                rq.len  = nbyte;
                req_port.write(rq);
                seq_item_port.get_next_item(rsp);
                v    = rsp.data.size() > 0 ? rsp.data[0] : 8'h00;
                last = rsp.t_end;
                seq_item_port.item_done();
            end else begin
                v    = regs[ptr];
                last = (ptr == cfg.nregs - 1);
            end
        end else begin
            case (ccc)
                I3C_CCC_GETPID:    begin v = cfg.pid[47 - 8 * nbyte -: 8]; last = (nbyte == 5); end
                I3C_CCC_GETBCR:    v = cfg.bcr;
                I3C_CCC_GETDCR:    v = cfg.dcr;
                I3C_CCC_GETMWL:    begin v = (nbyte == 0) ? mwl[15:8] : mwl[7:0]; last = (nbyte == 1); end
                I3C_CCC_GETSTATUS: begin v = (nbyte == 0) ? 8'h00 : {2'b00, perr, 4'b0000, ibi_pending}; last = (nbyte == 1); end
                default: ;
            endcase
        end
    endtask

    // a private write byte (index nbyte: 0 = register pointer)
    task wr_priv(bit [7:0] v);
        if (cfg.slv_mode == ODVE_I3C_SLV_SEQ) begin
            odve_i3c_item rq = odve_i3c_item::type_id::create("rq"), rsp;
            rq.kind = I3C_PRIV_WR;
            rq.addr = da;
            rq.len  = nbyte;
            rq.data.push_back(v);
            req_port.write(rq);
            seq_item_port.get_next_item(rsp);
            seq_item_port.item_done();
        end else if (nbyte == 0) begin
            ptr = 32'(v) % cfg.nregs;
        end else begin
            regs[ptr] = v;
            ptr = (ptr + 1) % cfg.nregs;
        end
    endtask

    function void drive(bit oe, bit o, bit pp);
        vif.t_sda_oe <= oe;
        vif.t_sda_o  <= o;
        vif.t_sda_pp <= pp;
    endfunction

    // one clk of the state machine
    task step();
        bit rise  =  s_scl && !scl_q;
        bit fall  = !s_scl &&  scl_q;
        bit start =  s_scl &&  scl_q &&  sda_q && !s_sda;
        bit stop  =  s_scl &&  scl_q && !sda_q &&  s_sda;
        bit [7:0] hdr = {sr[6:0], s_sda};
        scl_q = s_scl;
        sda_q = s_sda;

        if (stop) begin
            st = S_IDLE; drive(0, 0, 0);
            ctx = CTX_NONE; entdaa = 0; arb = 0; req_drv = 0; ibi_tx = 0; idle_cnt = 0;
        end else if (start) begin
            arb_hj = 0;
            if (st == S_IDLE && hj_ok())       begin arb = 1; arb_hj = 1; end
            else if (st == S_IDLE && ibi_ok()) begin arb = 1; arb_hj = 0; end
            else arb = 0;
            if (st != S_IDLE && ctx == CTX_BC) ctx = CTX_NONE;
            st = S_HDR; bcnt = 0; ibi_tx = 0;
            if (!req_drv) drive(0, 0, 0);
        end else if (rise) begin
            case (st)
                S_HDR: begin
                    bit [7:0] mh = my_hdr();
                    sr = hdr;
                    if (arb && mh[7 - bcnt] && !s_sda) arb = 0;
                    bcnt++;
                    if (bcnt == 8) begin
                        bcnt = 0; nbyte = 0;
                        if (arb && hdr == mh) st = S_IBIACK;
                        else if (hdr[7:1] == I3C_BCAST && !hdr[0]) begin
                            st = S_ACK; nxt = S_CCC; ctx = CTX_NONE; entdaa = 0;
                        end else if (hdr[7:1] == I3C_BCAST && hdr[0] && entdaa && !has_da) begin
                            st = S_ACK; nxt = S_DAAID;
                        end else if (ctx == CTX_DIR && has_da && hdr[7:1] == da && dir_ok(ccc, hdr[0])) begin
                            st = S_ACK; nxt = hdr[0] ? S_RD : S_WR; is_ccc = 1;
                        end else if (ctx == CTX_DIR && ccc == I3C_CCC_SETDASA && !has_da && cfg.static_addr != 0
                                     && hdr[7:1] == cfg.static_addr && !hdr[0]) begin
                            st = S_ACK; nxt = S_WR; is_ccc = 1;
                        end else if (ctx != CTX_DIR && has_da && hdr[7:1] == da) begin
                            st = S_ACK; nxt = hdr[0] ? S_RD : S_WR; is_ccc = 0;
                        end else st = S_IGN;
                        arb = 0;
                        if (st != S_IBIACK) arb_hj = 0;
                    end
                end
                S_ACK: begin st = nxt; bcnt = 0; end
                S_IBIACK: begin
                    if (arb_hj) begin
                        hj_pending = 0;                       // ACKed or not, the request is over
                        st = S_IGN;
                    end else if (s_sda) st = S_IGN;           // IBI NACKed: stays pending
                    else if (cfg.bcr[2]) begin st = S_RD; ibi_tx = 1; is_ccc = 0; nbyte = 0; bcnt = 0; end
                    else begin st = S_IGN; ibi_pending = 0; end
                    arb_hj = 0;
                end
                S_CCC, S_WR: begin
                    if (bcnt < 8) begin
                        sr = {sr[6:0], s_sda};
                        bcnt++;
                    end else begin
                        bcnt = 0;
                        if (s_sda != i3c_par8(sr)) begin
                            perr = 1;
                            st = S_IGN;
                        end else if (st == S_CCC) begin
                            ccc = sr; nbyte = 0;
                            if (sr == I3C_CCC_ENTDAA)      begin entdaa = 1; st = S_IGN; end
                            else if (sr == I3C_CCC_RSTDAA) begin has_da = 0; st = S_IGN; end
                            else if (!sr[7])               begin ctx = CTX_BC; st = S_WR; is_ccc = 1; end
                            else                           begin ctx = CTX_DIR; st = S_IGN; end
                        end else begin
                            if (!is_ccc) wr_priv(sr);
                            else case (ccc)
                                I3C_CCC_ENEC_B, I3C_CCC_ENEC_D:     begin enint |= sr[0]; enhj |= sr[3]; end
                                I3C_CCC_DISEC_B, I3C_CCC_DISEC_D:   begin enint &= ~sr[0]; enhj &= ~sr[3]; end
                                I3C_CCC_SETMWL_B, I3C_CCC_SETMWL_D: begin
                                    if (nbyte == 0)      mwl[15:8] = sr;
                                    else if (nbyte == 1) mwl[7:0]  = sr;
                                end
                                I3C_CCC_SETDASA: if (nbyte == 0) begin da = sr[7:1]; has_da = 1; end
                                default: ;
                            endcase
                            nbyte++;
                        end
                    end
                end
                S_RD: begin
                    if (bcnt < 8) bcnt++;
                    else begin
                        bcnt = 0;
                        nbyte++;
                        if (!is_ccc && !ibi_tx && cfg.slv_mode == ODVE_I3C_SLV_MEM) ptr = (ptr + 1) % cfg.nregs;
                        if (is_ccc && ccc == I3C_CCC_GETSTATUS && tx_last) perr = 0;
                        if (ibi_tx && tx_last) ibi_pending = 0;
                        if (tx_last) st = S_IGN;
                        else         drive(0, 0, 0);
                    end
                end
                S_DAAID: begin
                    bit [63:0] id = daa_id();
                    if (id[63 - bcnt] && !s_sda) st = S_IGN;
                    else if (bcnt == 63) begin st = S_DAAADR; bcnt = 0; end
                    else bcnt++;
                end
                S_DAAADR: begin
                    sr = {sr[6:0], s_sda};
                    if (bcnt == 7) begin
                        bcnt = 0;
                        if (s_sda == ~^sr[7:1]) begin new_da = sr[7:1]; st = S_DAAACK; end
                        else st = S_IGN;
                    end else bcnt++;
                end
                S_DAAACK: begin da = new_da; has_da = 1; st = S_IGN; end
                default: ;
            endcase
        end else if (fall) begin
            req_drv = 0;
            case (st)
                S_HDR: begin
                    bit [7:0] mh = my_hdr();
                    drive(arb ? !mh[7 - bcnt] : 1'b0, 0, 0);
                end
                S_ACK, S_DAAACK: drive(1, 0, 0);
                S_RD: begin
                    if (bcnt == 0) rd_next(tx, tx_last);
                    if (bcnt < 8) drive(1, tx[7 - bcnt], 1);
                    else          drive(1, !tx_last, 1);
                end
                S_DAAID: begin
                    bit [63:0] id = daa_id();
                    drive(!id[63 - bcnt], 0, 0);
                end
                default: drive(0, 0, 0);
            endcase
        end else if (st == S_IDLE) begin
            if (s_scl && s_sda) idle_cnt++;
            else idle_cnt = 0;
            if ((ibi_ok() || hj_ok()) && !req_drv && s_scl && s_sda && idle_cnt >= cfg.t_aval) begin
                drive(1, 0, 0);
                req_drv = 1;
            end
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        regs = new[cfg.nregs];
        drive(0, 0, 0);
        wait (vif.rst_n === 1'b1);
        forever begin
            @(negedge vif.clk);
            s_scl = vif.scl;
            s_sda = vif.sda;
            @(posedge vif.clk);
            if (cfg.offline) begin
                scl_q = s_scl; sda_q = s_sda; st = S_IDLE;
                continue;
            end
            step();
        end
    endtask
endclass
