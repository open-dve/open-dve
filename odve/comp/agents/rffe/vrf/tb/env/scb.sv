// Reference model of the two slaves' register files (USID 5 and A, NREG
// registers each), fed by the master agent's monitor. Writes update the
// model the way an RFFE slave must take them: broadcast (USID 0) writes go
// to both slaves; a parity error in the command or an address frame drops
// the whole sequence; a parity error in a data frame drops that frame and
// the ones after it; registers beyond NREG are not written. Every read data
// frame is compared with the model: data from an implemented register, a
// No Response Frame from an unimplemented one, from an absent USID or after
// a parity error in the request.
`uvm_analysis_imp_decl(_rffe)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_rffe #(odve_rffe_item, scb) rffe_imp;

    bit [3:0]    usids[$] = '{4'h5, 4'hA};
    int unsigned nregs    = 64;
    bit [7:0]    model [bit [3:0]][int unsigned];
    int unsigned n_wr = 0, n_rd = 0, n_bytes = 0, n_nrf = 0, n_par_err = 0, n_bcast = 0, n_half = 0;
    int          exp_par_err = -1;   // a test injecting parity errors sets the number it sent

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rffe_imp = new("rffe_imp", this);
    endfunction

    function bit present(bit [3:0] u);
        foreach (usids[i]) if (usids[i] == u) return 1;
        return 0;
    endfunction

    function bit [7:0] get(bit [3:0] u, int unsigned a);
        if (model.exists(u) && model[u].exists(a)) return model[u][a];
        return 8'h00;
    endfunction

    function void write_rffe(odve_rffe_item tr);
        bit dropped = tr.cmd_par_err || tr.addr_par_err;
        if (dropped || tr.data_par_err_idx >= 0) n_par_err++;
        if (tr.half_speed) n_half++;
        if (!tr.is_read()) begin
            n_wr++;
            if (tr.usid == 4'h0) n_bcast++;
            if (dropped) return;
            foreach (usids[k]) begin
                bit [3:0] u = usids[k];
                if (tr.usid != u && tr.usid != 4'h0) continue;
                if (tr.kind == ODVE_RFFE_REG0_WR) begin
                    model[u][0] = {1'b0, tr.data[0][6:0]};
                end else begin
                    foreach (tr.data[i]) begin
                        int unsigned a = tr.byte_addr(i);
                        if (tr.data_par_err_idx >= 0 && i >= tr.data_par_err_idx) break;
                        if (a < nregs) model[u][a] = tr.data[i];
                    end
                end
            end
        end else begin
            n_rd++;
            for (int i = 0; i < int'(tr.nbytes); i++) begin
                int unsigned a   = tr.byte_addr(i);
                bit          nrf = dropped || !present(tr.usid) || a >= nregs;
                bit [7:0]    exp = nrf ? 8'h00 : get(tr.usid, a);
                n_bytes++;
                if (tr.nrf_mask[i]) n_nrf++;
                if (tr.nrf_mask[i] != nrf || tr.data[i] !== exp)
                    `uvm_error(get_name(), $sformatf("%s: frame %0d (addr 0x%0h) is %s0x%02h, expected %s0x%02h",
                        tr.convert2string(), i, a, tr.nrf_mask[i] ? "NRF " : "", tr.data[i], nrf ? "NRF " : "", exp))
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d writes (%0d broadcast), %0d reads (%0d data frames, %0d NRF, %0d half speed), %0d with a parity error",
                                        n_wr, n_bcast, n_rd, n_bytes, n_nrf, n_half, n_par_err), UVM_LOW)
        if (n_wr + n_rd == 0)
            `uvm_error(get_name(), "no RFFE command sequences observed")
        if (exp_par_err >= 0 && n_par_err != exp_par_err)
            `uvm_error(get_name(), $sformatf("%0d sequences with a parity error observed, %0d injected", n_par_err, exp_par_err))
    endfunction
endclass : scb
