// Reference model of the slaves' command protocol (vrf/dut/dut.sv, and the
// slave agent's odve_spi_slv_model, which must behave the same): one 64-byte
// register file per chip select. Every frame the monitor reports is decoded
// with the slave's format: word 0 out must be the ID, read data must match
// the model, write data updates it; an incomplete last word is dropped.
// Frames in which the monitor flagged a protocol violation (injected by the
// error tests) are not checked on MISO, their effect on the model still is.
`uvm_analysis_imp_decl(_spi)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_spi #(odve_spi_item, scb) spi_imp;

    localparam int NB = 64;
    bit [7:0]    id [2] = '{8'hA5, 8'h3C};
    bit [7:0]    model [2][NB];
    int unsigned n_frames = 0, n_wr = 0, n_rd = 0, n_bytes_chk = 0, n_abort = 0, n_skip = 0;

    `odve_cov_create(spi_reg_cg)

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        spi_imp = new("spi_imp", this);
        foreach (model[c, a]) model[c][a] = 8'h00;
    endfunction

    function bit [31:0] mask(int unsigned bits);
        return (bits >= 32) ? 32'hFFFF_FFFF : ((32'h1 << bits) - 1);
    endfunction

    function void write_spi(odve_spi_item tr);
        int unsigned c = tr.cs, W = tr.word_bits, B = (tr.word_bits + 7) / 8;
        bit          rd;
        int unsigned addr, ptr;
        n_frames++;
        if (tr.partial_bits) n_abort++;
        if (tr.proto_err)    n_skip++;
        if (c > 1) begin                                   // nobody there: only as an injected error
            if (!tr.proto_err) `uvm_error(get_name(), $sformatf("frame on cs%0d: this TB has two slaves", c))
            return;
        end
        if (tr.mosi.size() == 0) return;                   // not even a complete command word
        if (!tr.proto_err && tr.miso[0] !== ({4{id[c]}} & mask(W)))
            `uvm_error(get_name(), $sformatf("%s: word 0 out 0x%0h, expected ID 0x%0h", tr.convert2string(), tr.miso[0], {4{id[c]}} & mask(W)))
        rd   = tr.mosi[0][W - 1];
        addr = tr.mosi[0][5:0];
        ptr  = addr;
        for (int n = 1; n < tr.mosi.size(); n++) begin
            bit [31:0] exp = '0;
            for (int k = 0; k < B; k++) begin
                if (rd) exp[8*k +: 8] = model[c][(ptr + k) % NB];
                else    model[c][(ptr + k) % NB] = tr.mosi[n][8*k +: 8];
            end
            exp &= mask(W);
            if (rd && !tr.proto_err) begin
                n_bytes_chk += B;
                if (tr.miso[n] !== exp)
                    `uvm_error(get_name(), $sformatf("%s: read word %0d (addr 0x%02h) = 0x%0h, expected 0x%0h", tr.convert2string(), n, ptr % NB, tr.miso[n], exp))
            end
            ptr = (ptr + B) % NB;
        end
        if (rd) n_rd++; else n_wr++;
        `odve_cov_sample(spi_reg_cg, rd, c, addr, (tr.mosi.size() - 1) * B, addr + (tr.mosi.size() - 1) * B > NB)
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d frames: %0d writes, %0d reads (%0d bytes checked), %0d aborted, %0d not checked (protocol error)",
                                        n_frames, n_wr, n_rd, n_bytes_chk, n_abort, n_skip), UVM_LOW)
        if (n_frames == 0)
            `uvm_error(get_name(), "no SPI frames observed")
    endfunction
endclass : scb
