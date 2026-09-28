// Reference model of the slave's register file: writes update it, reads are
// compared against it; an out-of-range transfer must carry pslverr.
`uvm_analysis_imp_decl(_apb)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_apb #(odve_apb_item, scb) apb_imp;

    int unsigned nregs = 16;
    bit [31:0]   model [int unsigned];
    int unsigned n_wr = 0, n_rd = 0, n_err = 0;

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_imp = new("apb_imp", this);
    endfunction

    function void write_apb(odve_apb_item tr);
        int unsigned idx = tr.addr >> 2;
        bit in_range = idx < nregs;
        if (tr.slverr != !in_range)
            `uvm_error(get_name(), $sformatf("%s: pslverr=%0b but address %s range", tr.convert2string(), tr.slverr, in_range ? "in" : "out of"))
        if (tr.slverr) n_err++;
        if (tr.write) begin
            n_wr++;
            if (in_range) model[idx] = tr.data;
        end else begin
            bit [31:0] exp = in_range ? (model.exists(idx) ? model[idx] : 32'h0) : 32'h0;
            n_rd++;
            if (tr.data !== exp)
                `uvm_error(get_name(), $sformatf("%s: read data 0x%08h, expected 0x%08h", tr.convert2string(), tr.data, exp))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d writes, %0d reads, %0d slverr transfers checked", n_wr, n_rd, n_err), UVM_LOW)
        if (n_wr + n_rd == 0)
            `uvm_error(get_name(), "no APB transfers observed")
    endfunction
endclass : scb
