// Reference model of the flash (written independently of the agent's
// odve_qspi_flash_model; the RTL flash and the slave agent must both match
// it). Every frame from the monitor is checked against the expected flash
// state and then applied to it:
//   - whether the flash takes the command: opcode valid in the mode, not
//     BUSY (except 05h/35h), QE for quad instructions; an ignored read-type
//     command must leave the data lines undriven (pull-ups: all FFh);
//   - read data (array, status, JEDEC ID, SFDP);
//   - WEL / QE / program (AND, page wrap) / erase effects, only with WEL
//     and with cs_n raised on the right boundary.
// BUSY ends when the flash says so: after a program / erase / status write
// the model is busy until a status read returns BUSY = 0 (tests poll); while
// busy, status bytes must show WEL = 1, and BUSY may fall but never rise.
`uvm_analysis_imp_decl(_qspi)

class scb extends uvm_component;
    `uvm_component_utils(scb)

    uvm_analysis_imp_qspi #(odve_qspi_item, scb) qspi_imp;
    odve_qspi_cfg cfg;

    localparam int MEM = 8192;
    bit [7:0]    mem [MEM];
    bit          wel = 0, qe = 0, busy = 0;
    int unsigned n_frames = 0, n_rd_bytes = 0, n_prog = 0, n_erase = 0, n_ignored = 0, n_unchecked = 0;

    `odve_cov_create(qspi_flash_cg)

    function new(string name = "scb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        qspi_imp = new("qspi_imp", this);
        foreach (mem[i]) mem[i] = 8'hFF;
    endfunction

    function bit [7:0] sfdp(bit [7:0] a);
        bit [31:0] d = MEM * 8 - 1;
        bit [7:0]  hdr [16] = '{8'h53, 8'h46, 8'h44, 8'h50, 8'h06, 8'h01, 8'h00, 8'hFF,
                                8'h00, 8'h06, 8'h01, 8'h09, 8'h80, 8'h00, 8'h00, 8'hFF};
        if (a < 16) return hdr[a];
        if (a >= 8'h84 && a <= 8'h87) return d[8 * (a - 8'h84) +: 8];
        return 8'hFF;
    endfunction

    function int kind_of(bit [7:0] c);
        case (c)
            QSPI_READ, QSPI_FREAD, QSPI_DOR, QSPI_DIOR, QSPI_QOR, QSPI_QIOR: return 0;
            QSPI_PP, QSPI_QPP:      return 1;
            QSPI_SE:                return 2;
            QSPI_WRSR2:             return 3;
            QSPI_WREN:              return 4;
            QSPI_WRDI:              return 5;
            QSPI_RDSR1, QSPI_RDSR2: return 6;
            QSPI_RDID:              return 7;
            QSPI_SFDP:              return 8;
            default:                return 9;
        endcase
    endfunction

    function void err(odve_qspi_item tr, string msg);
        `uvm_error(get_name(), $sformatf("%s: %s", tr.convert2string(), msg))
    endfunction

    function void write_qspi(odve_qspi_item tr);
        odve_qspi_fmt_t f = odve_qspi_fmt(tr.cmd, tr.qpi, cfg.bus.qpi_dummy);
        int unsigned    hdr = odve_qspi_hdr_clks(f);
        bit             exact = !tr.truncated && tr.partial_bits == 0;
        bit             taken;
        int             outcome = 0;
        bit             wrap = 0, over = 0, busy_seen = 0;
        n_frames++;
        if (!f.valid || tr.nclk < 8 / f.cmd_lanes) return;     // unknown opcode / not even an instruction

        taken = !(busy && !(tr.cmd inside {QSPI_RDSR1, QSPI_RDSR2})) && !(f.needs_qe && !qe);
        if (!taken) begin
            outcome = busy ? 1 : 3;
            n_ignored++;
            foreach (tr.rdata[i])
                if (tr.rdata[i] !== 8'hFF) begin err(tr, $sformatf("ignored command (%s), yet byte %0d = %02h, not the pull-up FFh", busy ? "busy" : "QE = 0", i, tr.rdata[i])); break; end
            `odve_cov_sample(qspi_flash_cg, kind_of(tr.cmd), outcome, 0, 0, 0)
            return;
        end

        // read-type data
        if (f.data_out && tr.proto_err) n_unchecked++;
        else if (f.data_out) begin
            foreach (tr.rdata[i]) begin
                bit [7:0] exp;
                case (tr.cmd)
                    QSPI_RDSR1: begin
                        bit b = tr.rdata[i][0];
                        if (b) busy_seen = 1;
                        if (b && !busy) err(tr, $sformatf("status byte %0d: BUSY set with no operation running", i));
                        if (busy && !b) begin busy = 0; wel = 0; end      // the operation ended
                        exp = {6'b0, (busy ? 1'b1 : wel), busy};
                    end
                    QSPI_RDSR2: exp = {6'b0, qe, 1'b0};
                    QSPI_RDID:  exp = (i % 3 == 0) ? 8'hEF : (i % 3 == 1) ? (tr.qpi ? 8'h60 : 8'h40) : 8'h0D;
                    QSPI_SFDP:  exp = sfdp(8'(tr.addr[7:0] + i));
                    default:    begin exp = mem[(tr.addr + i) % MEM]; if ((tr.addr % MEM) + i >= MEM) wrap = 1; end
                endcase
                if (tr.rdata[i] !== exp) begin err(tr, $sformatf("byte %0d = %02h, expected %02h", i, tr.rdata[i], exp)); break; end
                n_rd_bytes++;
            end
        end

        // effects at cs_n rise
        case (tr.cmd)
            QSPI_WREN:  wel = 1;
            QSPI_WRDI:  wel = 0;
            QSPI_WRSR2: if (!wel) outcome = 2;
                        else if (!exact || tr.wdata.size() != 1) outcome = 4;
                        else begin qe = tr.wdata[0][1]; busy = 1; end
            QSPI_PP, QSPI_QPP:
                        if (!wel) outcome = 2;
                        else if (!exact || tr.wdata.size() == 0) outcome = 4;
                        else begin
                            int unsigned base = (tr.addr % MEM) & ~32'hFF;
                            bit [7:0]    pb [int unsigned];
                            foreach (tr.wdata[i]) begin
                                pb[(tr.addr[7:0] + i) % 256] = tr.wdata[i];
                                if (tr.addr[7:0] + i >= 256) wrap = 1;
                            end
                            foreach (pb[k]) begin
                                if (pb[k] & ~mem[base + k]) over = 1;
                                mem[base + k] &= pb[k];
                            end
                            busy = 1;
                            n_prog++;
                        end
            QSPI_SE:    if (!wel) outcome = 2;
                        else if (!exact || tr.nclk != hdr) outcome = 4;
                        else begin
                            int unsigned base = (tr.addr % MEM) & ~32'hFFF;
                            for (int k = 0; k < 4096; k++) mem[base + k] = 8'hFF;
                            busy = 1;
                            n_erase++;
                        end
            default: ;
        endcase
        `odve_cov_sample(qspi_flash_cg, kind_of(tr.cmd), outcome, wrap, over, busy_seen)
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info(get_name(), $sformatf("%0d frames: %0d data bytes read and checked, %0d programs, %0d erases, %0d ignored commands, %0d reads not checked (protocol error)",
                                        n_frames, n_rd_bytes, n_prog, n_erase, n_ignored, n_unchecked), UVM_LOW)
        if (n_frames == 0) `uvm_error(get_name(), "no QSPI frames observed")
    endfunction
endclass : scb
