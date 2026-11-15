// Reference model of the two slaves (SID 5 and A): NREG read/write registers
// each, the power state at address NREG, fed by the master agent's monitor.
// Every non-read command is checked for the ACK/NACK bit the slave must
// give: ACK when the SID is present and every frame had good parity, NACK
// (the parked 0) otherwise. Writes update the model as an SPMI slave must
// take them: a bad command or address frame drops the whole sequence, a bad
// data frame drops itself and the frames after it; registers at and beyond
// NREG are not written. Reset clears a slave's registers and sets ACTIVE,
// Sleep / Shutdown / Wakeup set the state. Every read data frame is compared
// with the model: register data, the power state at NREG, a No Response
// Frame beyond it, from an absent SID or after a bad command/address frame.
`uvm_analysis_imp_decl(_spmi)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_spmi #(odve_spmi_item, scb) spmi_imp;

    bit [3:0]      sids[$] = '{4'h5, 4'hA};
    int unsigned   nregs   = 64;
    bit [7:0]      model [bit [3:0]][int unsigned];
    odve_spmi_pm_e pm    [bit [3:0]];
    int unsigned   n_wr = 0, n_rd = 0, n_pm = 0, n_bytes = 0, n_nrf = 0, n_par_err = 0, n_ack = 0, n_nack = 0;
    int            exp_par_err = -1;   // a test injecting parity errors sets the number it sent

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        spmi_imp = new("spmi_imp", this);
    endfunction

    function bit present(bit [3:0] s);
        foreach (sids[i]) if (sids[i] == s) return 1;
        return 0;
    endfunction

    function bit [7:0] get(bit [3:0] s, int unsigned a);
        if (a == nregs) return {6'h00, pm.exists(s) ? pm[s] : ODVE_SPMI_ACTIVE};
        if (model.exists(s) && model[s].exists(a)) return model[s][a];
        return 8'h00;
    endfunction

    function void write_spmi(odve_spmi_item tr);
        bit [3:0] s       = tr.sid;
        bit       dropped = tr.cmd_par_err || tr.addr_par_err;
        bit       here    = present(s);
        if (dropped || tr.data_par_err_idx >= 0) n_par_err++;
        if (!tr.is_read()) begin
            bit exp_ack = here && !dropped && tr.data_par_err_idx < 0;
            if (tr.is_pm()) n_pm++; else n_wr++;
            if (tr.ack) n_ack++; else n_nack++;
            if (tr.ack != exp_ack)
                `uvm_error(get_name(), $sformatf("%s: %s, expected %s", tr.convert2string(), tr.ack ? "ACK" : "NACK", exp_ack ? "ACK" : "NACK"))
            if (dropped || !here) return;
            case (tr.kind)
                ODVE_SPMI_REG0_WR:  model[s][0] = {1'b0, tr.data[0][6:0]};
                ODVE_SPMI_RESET: begin
                    if (model.exists(s)) model[s].delete();
                    pm[s] = ODVE_SPMI_ACTIVE;
                end
                ODVE_SPMI_SLEEP:    pm[s] = ODVE_SPMI_SLEEPING;
                ODVE_SPMI_SHUTDOWN: pm[s] = ODVE_SPMI_SHUTDOWN_ST;
                ODVE_SPMI_WAKEUP:   pm[s] = ODVE_SPMI_ACTIVE;
                default:
                    foreach (tr.data[i]) begin
                        int unsigned a = tr.byte_addr(i);
                        if (tr.data_par_err_idx >= 0 && i >= tr.data_par_err_idx) break;
                        if (a < nregs) model[s][a] = tr.data[i];
                    end
            endcase
        end else begin
            n_rd++;
            for (int i = 0; i < int'(tr.nbytes); i++) begin
                int unsigned a   = tr.byte_addr(i);
                bit          nrf = dropped || !here || a > nregs;
                bit [7:0]    exp = nrf ? 8'h00 : get(s, a);
                n_bytes++;
                if (tr.nrf_mask[i]) n_nrf++;
                if (tr.nrf_mask[i] != nrf || tr.data[i] !== exp)
                    `uvm_error(get_name(), $sformatf("%s: frame %0d (addr 0x%0h) is %s0x%02h, expected %s0x%02h",
                        tr.convert2string(), i, a, tr.nrf_mask[i] ? "NRF " : "", tr.data[i], nrf ? "NRF " : "", exp))
            end
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d writes, %0d PM commands (%0d ACK, %0d NACK), %0d reads (%0d data frames, %0d NRF), %0d with a parity error",
                                        n_wr, n_pm, n_ack, n_nack, n_rd, n_bytes, n_nrf, n_par_err), UVM_LOW)
        if (n_wr + n_rd + n_pm == 0)
            `uvm_error(get_name(), "no SPMI command sequences observed")
        if (exp_par_err >= 0 && n_par_err != exp_par_err)
            `uvm_error(get_name(), $sformatf("%0d sequences with a parity error observed, %0d injected", n_par_err, exp_par_err))
    endfunction
endclass : scb
