// Reference model of the TAP chain: one odve_jtag_tap_model per TAP, tap[0]
// nearest TDI. For every scan the monitor reports, the chain is rebuilt from
// what each TAP captures (Capture-IR 0001, or the data register its
// instruction selects), shifted bit by bit exactly as long as the scan was
// (TDI into tap[0]'s MSB, each TAP's LSB into the next one, the last TAP's
// LSB on TDO), every bit out compared with TDO, and what is left in each
// TAP's register applied at Update. A reset selects IDCODE everywhere; one
// through TRST_n also clears USERDATA and the boundary latch.
`uvm_analysis_imp_decl(_jtag)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_jtag #(odve_jtag_item, scb) jtag_imp;

    odve_jtag_tap_model taps [$];
    int unsigned n_ir = 0, n_dr = 0, n_rst = 0, n_bits = 0, n_mismatch = 0;
    bit          ignore_ir_tdo = 0;     // set by a test injecting a Capture-IR fault

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        jtag_imp = new("jtag_imp", this);
    endfunction

    function void write_jtag(odve_jtag_item tr);
        odve_jtag_vec_t reg_v [$];
        int unsigned    reg_len [$];
        odve_jtag_vec_t exp_tdo = '0;
        bit             in_bit, out_bit;
        int unsigned    n = taps.size();
        if (tr.kind == JTAG_RESET) begin
            n_rst++;
            foreach (taps[k]) taps[k].reset(tr.via_trst);
            return;
        end
        // Capture
        for (int unsigned k = 0; k < n; k++) begin
            odve_jtag_vec_t v = '0;
            int unsigned    l;
            if (tr.kind == JTAG_IR) begin
                l = 4;
                v[3:0] = taps[k].capture_ir();
            end else taps[k].capture_dr(taps[k].ir, l, v);
            reg_v.push_back(v);
            reg_len.push_back(l);
        end
        // Shift
        for (int unsigned i = 0; i < tr.len; i++) begin
            in_bit = tr.tdi[i];
            for (int unsigned k = 0; k < n; k++) begin
                out_bit = reg_v[k][0];
                reg_v[k] = reg_v[k] >> 1;
                reg_v[k][reg_len[k] - 1] = in_bit;
                in_bit = out_bit;
            end
            exp_tdo[i] = in_bit;
        end
        // Compare
        if (!(tr.kind == JTAG_IR && ignore_ir_tdo)) begin
            for (int unsigned i = 0; i < tr.len; i++) begin
                if (tr.tdo[i] !== exp_tdo[i]) begin
                    n_mismatch++;
                    `uvm_error("SCB_TDO", $sformatf("%s: TDO bit %0d is %b, expected %b (expected TDO 0x%0h)",
                                                    tr.convert2string(), i, tr.tdo[i], exp_tdo[i], exp_tdo))
                    break;
                end
            end
        end
        n_bits += tr.len;
        // Update
        for (int unsigned k = 0; k < n; k++) begin
            if (tr.kind == JTAG_IR) taps[k].update_ir(reg_v[k]);
            else                    taps[k].update_dr(taps[k].ir, reg_v[k]);
        end
        if (tr.kind == JTAG_IR) n_ir++; else n_dr++;
    endfunction

    // instruction / user register of TAP k as the model has them (for tests)
    function bit [3:0]  ir_of(int unsigned k);   return taps[k].ir;   endfunction
    function bit [31:0] user_of(int unsigned k); return taps[k].user; endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d TAP(s): %0d IR scans, %0d DR scans, %0d resets, %0d TDO bits checked, %0d mismatches",
                                        taps.size(), n_ir, n_dr, n_rst, n_bits, n_mismatch), UVM_LOW)
        if (n_ir + n_dr == 0)
            `uvm_error(get_name(), "no JTAG scans observed")
    endfunction
endclass : scb
