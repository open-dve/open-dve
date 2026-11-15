// Reference model of every target on the bus (identity, dynamic address,
// event enables, MWL, protocol-error status, register file + pointer), fed by
// the controller agent's monitor. Checks: who ACKs which address, ENTDAA
// arbitration order (the lowest {PID, BCR, DCR} wins each round), address
// parity handling, private read data and the target's end-of-data T-bit,
// GET CCC payloads, the effect of parity errors (rest of the transfer
// ignored, GETSTATUS[5]), and that IBIs / Hot-Joins come only from targets
// allowed to send them, with the expected Mandatory Data Byte.
class i3c_tgt_model extends uvm_object;
    `uvm_object_utils(i3c_tgt_model)

    string       tag;
    bit          online = 1;
    bit [47:0]   pid;
    bit [7:0]    bcr, dcr;
    bit [6:0]    sa;
    bit          has_da;
    bit [6:0]    da;
    bit          enint = 1, enhj = 1;
    bit [15:0]   mwl = 16'h0010;
    bit          perr;
    bit [7:0]    regs [NREGS];
    int unsigned ptr;
    bit [7:0]    exp_mdb[$];      // MDBs the test expects from this target's IBIs, in order
    int unsigned n_ibi_ack, n_ibi_nack, n_hj;

    function new(string name = "i3c_tgt_model");
        super.new(name);
    endfunction
    function bit [63:0] id();
        return {pid, bcr, dcr};
    endfunction
endclass

`uvm_analysis_imp_decl(_i3c)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_i3c #(odve_i3c_item, scb) i3c_imp;

    i3c_tgt_model models[$];
    i3c_tgt_model m_dut, m_tgt;   // null when absent
    int unsigned  n_items, n_wr, n_rd, n_ccc, n_daa_rounds, n_ibi, n_hj, n_perr;
    bit [6:0]     ibi_order[$];   // addresses of ACKed IBIs, in bus order

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        i3c_imp = new("i3c_imp", this);
    endfunction

    function i3c_tgt_model add(string tag, bit [47:0] pid, bit [7:0] bcr, bit [7:0] dcr, bit [6:0] sa);
        i3c_tgt_model m = i3c_tgt_model::type_id::create(tag);
        m.tag = tag; m.pid = pid; m.bcr = bcr; m.dcr = dcr; m.sa = sa;
        models.push_back(m);
        return m;
    endfunction

    function i3c_tgt_model by_da(bit [6:0] a);
        foreach (models[i]) if (models[i].online && models[i].has_da && models[i].da == a) return models[i];
        return null;
    endfunction

    function int unsigned n_online();
        int unsigned n = 0;
        foreach (models[i]) if (models[i].online) n++;
        return n;
    endfunction

    function void chk(bit cond, string msg);
        if (!cond) `uvm_error(get_name(), msg)
    endfunction

    // write payload, up to the first byte with a wrong T-bit (the target
    // drops it and everything after it)
    function void apply_wr(i3c_tgt_model m, odve_i3c_item tr);
        foreach (tr.data[i]) begin
            if (tr.perr_idx >= 0 && i >= tr.perr_idx) begin m.perr = 1; break; end
            if (tr.kind == I3C_PRIV_WR) begin
                if (i == 0) m.ptr = 32'(tr.data[i]) % NREGS;
                else begin m.regs[m.ptr] = tr.data[i]; m.ptr = (m.ptr + 1) % NREGS; end
            end else case (tr.ccc)
                I3C_CCC_ENEC_B, I3C_CCC_ENEC_D:     begin m.enint |= tr.data[i][0]; m.enhj |= tr.data[i][3]; end
                I3C_CCC_DISEC_B, I3C_CCC_DISEC_D:   begin m.enint &= ~tr.data[i][0]; m.enhj &= ~tr.data[i][3]; end
                I3C_CCC_SETMWL_B, I3C_CCC_SETMWL_D: if (i == 0) m.mwl[15:8] = tr.data[i]; else if (i == 1) m.mwl[7:0] = tr.data[i];
                I3C_CCC_SETDASA:                    if (i == 0) begin m.da = tr.data[i][7:1]; m.has_da = 1; end
                default: ;
            endcase
        end
    endfunction

    function void write_i3c(odve_i3c_item tr);
        i3c_tgt_model m;
        string        s = tr.convert2string();
        n_items++;
        if (tr.n_perr > 0) n_perr++;
        case (tr.kind)
            I3C_PRIV_WR, I3C_PRIV_RD: begin
                m = by_da(tr.addr);
                chk(tr.ack == (m != null), $sformatf("%s: ACK=%0b, expected %0b (%s)", s, tr.ack, m != null,
                                                    m != null ? m.tag : "no target at this address"));
                if (tr.ack && m != null) begin
                    if (tr.kind == I3C_PRIV_WR) begin
                        n_wr++;
                        apply_wr(m, tr);
                    end else begin
                        n_rd++;
                        foreach (tr.data[k]) begin
                            bit last = (m.ptr == NREGS - 1);
                            chk(tr.data[k] == m.regs[m.ptr], $sformatf("%s: byte %0d = 0x%02h, register %0d of %s holds 0x%02h",
                                                                      s, k, tr.data[k], m.ptr, m.tag, m.regs[m.ptr]));
                            if (k < tr.data.size() - 1 || !tr.t_end)
                                chk(!last, $sformatf("%s: T=1 after byte %0d, but register %0d is the last (target must end)", s, k, m.ptr));
                            else
                                chk(last, $sformatf("%s: target ended (T=0) at register %0d, not the last one", s, m.ptr));
                            m.ptr = (m.ptr + 1) % NREGS;
                        end
                    end
                end
            end
            I3C_CCC_BC: begin
                n_ccc++;
                chk(tr.ack == (n_online() > 0), $sformatf("%s: 7E/W ACK=%0b with %0d target(s) on the bus", s, tr.ack, n_online()));
                foreach (models[i]) if (models[i].online) apply_wr(models[i], tr);
                if (tr.ccc == I3C_CCC_RSTDAA) foreach (models[i]) if (models[i].online) models[i].has_da = 0;
            end
            I3C_CCC_DW: begin
                bit known = tr.ccc inside {I3C_CCC_ENEC_D, I3C_CCC_DISEC_D, I3C_CCC_SETMWL_D, I3C_CCC_SETDASA};
                n_ccc++;
                m = null;
                if (tr.ccc == I3C_CCC_SETDASA) begin
                    foreach (models[i]) if (models[i].online && !models[i].has_da && models[i].sa == tr.addr && tr.addr != 0) m = models[i];
                end else m = by_da(tr.addr);
                chk(tr.ack == (m != null && known), $sformatf("%s: ACK=%0b, expected %0b", s, tr.ack, m != null && known));
                if (tr.ack && m != null) apply_wr(m, tr);
            end
            I3C_CCC_DR: begin
                bit [7:0] exp[$];
                n_ccc++;
                m = by_da(tr.addr);
                chk(tr.ack == (m != null && i3c_get_len(tr.ccc) > 0), $sformatf("%s: ACK=%0b, expected %0b", s, tr.ack, m != null));
                if (tr.ack && m != null) begin
                    case (tr.ccc)
                        I3C_CCC_GETPID:    for (int i = 5; i >= 0; i--) exp.push_back(m.pid[8 * i +: 8]);
                        I3C_CCC_GETBCR:    exp.push_back(m.bcr);
                        I3C_CCC_GETDCR:    exp.push_back(m.dcr);
                        I3C_CCC_GETMWL:    begin exp.push_back(m.mwl[15:8]); exp.push_back(m.mwl[7:0]); end
                        I3C_CCC_GETSTATUS: begin exp.push_back(8'h00); exp.push_back({2'b00, m.perr, 5'b0}); end
                        default: ;
                    endcase
                    chk(tr.data.size() == exp.size() && tr.t_end, $sformatf("%s: %0d byte(s), t_end=%0b; expected %0d ending with T=0",
                                                                           s, tr.data.size(), tr.t_end, exp.size()));
                    foreach (exp[i]) if (i < tr.data.size()) begin
                        bit [7:0] mask = (tr.ccc == I3C_CCC_GETSTATUS && i == 1) ? 8'hFE : 8'hFF;   // bit 0: IBI pending, the test checks it
                        chk((tr.data[i] & mask) == (exp[i] & mask), $sformatf("%s: byte %0d = 0x%02h, expected 0x%02h (%s)", s, i, tr.data[i], exp[i], m.tag));
                    end
                    if (tr.ccc == I3C_CCC_GETSTATUS) m.perr = 0;
                end
            end
            I3C_ENTDAA: begin
                n_ccc++;
                chk(tr.ack == (n_online() > 0), $sformatf("%s: 7E/W ACK=%0b with %0d target(s)", s, tr.ack, n_online()));
                foreach (tr.daa_id[r]) begin
                    i3c_tgt_model w = null;
                    n_daa_rounds++;
                    foreach (models[i])
                        if (models[i].online && !models[i].has_da && (w == null || models[i].id() < w.id())) w = models[i];
                    if (w == null) begin
                        `uvm_error(get_name(), $sformatf("%s: round %0d answered, but every target has an address", s, r))
                        continue;
                    end
                    chk(tr.daa_id[r] == w.id(), $sformatf("ENTDAA round %0d: ID %016h won, expected %016h (%s, lowest ID)", r, tr.daa_id[r], w.id(), w.tag));
                    chk(tr.daa_ack[r] == tr.daa_par_ok[r], $sformatf("ENTDAA round %0d: address 0x%02h parity_ok=%0b but ACK=%0b", r, tr.daa_da[r], tr.daa_par_ok[r], tr.daa_ack[r]));
                    if (tr.daa_ack[r]) begin
                        w.has_da = 1;
                        w.da     = tr.daa_da[r];
                        `uvm_info(get_name(), $sformatf("ENTDAA: %s (PID %012h) -> 0x%02h", w.tag, w.pid, w.da), UVM_LOW)
                    end
                end
                foreach (models[i]) if (models[i].online)
                    chk(models[i].has_da, $sformatf("after ENTDAA %s has no dynamic address", models[i].tag));
            end
            I3C_IBI: begin
                n_ibi++;
                m = by_da(tr.addr);
                if (m == null) `uvm_error(get_name(), $sformatf("%s: IBI from 0x%02h, no target has that address", s, tr.addr))
                else begin
                    chk(m.enint, $sformatf("%s: IBI from %s with events disabled (DISEC)", s, m.tag));
                    chk(m.bcr[1], $sformatf("%s: IBI from %s, whose BCR says not IBI capable", s, m.tag));
                    if (tr.ack) begin
                        m.n_ibi_ack++;
                        ibi_order.push_back(tr.addr);
                        if (m.bcr[2]) begin
                            chk(tr.data.size() >= 1 && tr.t_end, $sformatf("%s: IBI payload of %0d byte(s), t_end=%0b", s, tr.data.size(), tr.t_end));
                            if (m.exp_mdb.size() > 0 && tr.data.size() > 0) begin
                                bit [7:0] e = m.exp_mdb.pop_front();
                                chk(tr.data[0] == e, $sformatf("%s: MDB 0x%02h, expected 0x%02h", s, tr.data[0], e));
                            end
                        end else chk(tr.data.size() == 0, $sformatf("%s: payload from %s, whose BCR says none", s, m.tag));
                    end else m.n_ibi_nack++;
                end
            end
            I3C_HOTJOIN: begin
                bit any = 0;
                n_hj++;
                foreach (models[i]) if (models[i].online && !models[i].has_da && models[i].enhj) begin any = 1; models[i].n_hj++; end
                chk(any, $sformatf("%s: Hot-Join, but no target without an address (and Hot-Join enabled)", s));
            end
            default: ;
        endcase
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d transfers: %0d private writes, %0d private reads, %0d CCCs, %0d ENTDAA rounds, %0d IBIs, %0d Hot-Joins, %0d with parity errors",
                                        n_items, n_wr, n_rd, n_ccc, n_daa_rounds, n_ibi, n_hj, n_perr), UVM_LOW)
        foreach (models[i]) if (models[i].exp_mdb.size() > 0)
            `uvm_error(get_name(), $sformatf("%s: %0d expected IBI(s) never delivered", models[i].tag, models[i].exp_mdb.size()))
        if (n_items == 0) `uvm_error(get_name(), "no I3C transfers observed")
    endfunction
endclass : scb
