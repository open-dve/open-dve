// Behavioural serial NOR flash, the model behind the slave agent (MEM mode:
// in the driver; SEQ mode: in odve_qspi_slv_rsp_seq). Semantics after the
// W25Q32FV datasheet (doc/spec.md), scaled down:
//   - array of cfg.mem_bytes (address bits above it ignored), erased = FFh;
//     page program only clears bits (new = old & data), 256-byte page buffer
//     (data past the page end wraps to its start), sector erase sets 4 KiB to FFh;
//   - status 1 = {6'b0, WEL, BUSY}; status 2 = {6'b0, QE, 1'b0};
//     WREN sets WEL, WRDI clears it; PP/QPP/SE/WRSR2 need WEL, start BUSY for
//     tpp/tse/tw cycles and clear WEL when it ends;
//   - while BUSY only 05h/35h are accepted; quad commands (6Bh, EBh, 32h,
//     38h) need QE; PP/QPP only execute when cs_n rises on a byte boundary
//     with at least one byte, SE/WRSR2 only with exactly their bits.
// Time is the system clock cycle count the caller passes in.
class odve_qspi_flash_model extends uvm_object;
    `uvm_object_utils(odve_qspi_flash_model)

    odve_qspi_cfg cfg;
    bit [7:0]     mem [int unsigned];
    bit           wel, qe;
    longint       busy_until = 0;
    bit           op_pending = 0;
    int unsigned  n_exec = 0, n_ignored = 0;

    function new(string name = "odve_qspi_flash_model");
        super.new(name);
    endfunction

    function void update(longint now);
        if (op_pending && now >= busy_until) begin
            op_pending = 0;
            wel = 0;
        end
    endfunction

    function bit busy(longint now);
        update(now);
        return op_pending;
    endfunction

    function bit [7:0] peek(int unsigned a);
        a = a % cfg.mem_bytes;
        return mem.exists(a) ? mem[a] : 8'hFF;
    endfunction

    static function bit [7:0] sfdp_byte(bit [7:0] a, int unsigned mem_bytes);
        bit [31:0] bits_m1 = mem_bytes * 8 - 1;
        case (a)
            8'h00: return 8'h53;  8'h01: return 8'h46;  8'h02: return 8'h44;  8'h03: return 8'h50;  // "SFDP"
            8'h04: return 8'h06;  8'h05: return 8'h01;  8'h06: return 8'h00;  8'h07: return 8'hFF;  // rev 1.6, 1 header
            8'h08: return 8'h00;  8'h09: return 8'h06;  8'h0A: return 8'h01;  8'h0B: return 8'h09;  // BFP, rev 1.6, 9 DWORDs
            8'h0C: return 8'h80;  8'h0D: return 8'h00;  8'h0E: return 8'h00;  8'h0F: return 8'hFF;  // at 0x80, ID MSB FFh
            8'h84: return bits_m1[7:0];   8'h85: return bits_m1[15:8];                           // BFP DWORD2: density - 1 (bits)
            8'h86: return bits_m1[23:16]; 8'h87: return bits_m1[31:24];
            default: return 8'hFF;
        endcase
    endfunction

    // the flash takes the command (decoded from its opcode at time now)
    function bit accepts(bit [7:0] cmd, bit qpi, longint now);
        odve_qspi_fmt_t f = odve_qspi_fmt(cmd, qpi, cfg.bus.qpi_dummy);
        if (!f.valid) return 0;
        if (busy(now) && !(cmd inside {QSPI_RDSR1, QSPI_RDSR2})) return 0;
        if (f.needs_qe && !qe) return 0;
        return 1;
    endfunction

    // data byte i sent for an accepted read-type command
    function bit [7:0] out_byte(bit [7:0] cmd, bit qpi, bit [23:0] addr, int unsigned i, longint now);
        case (cmd)
            QSPI_RDSR1: return {6'b0, (busy(now) ? 1'b1 : wel), busy(now)};
            QSPI_RDSR2: return {6'b0, qe, 1'b0};
            QSPI_RDID:  case (i % 3)
                            0: return cfg.mfr_id;
                            1: return qpi ? cfg.type_qpi : cfg.type_spi;
                            default: return cfg.cap_id;
                        endcase
            QSPI_SFDP:  return sfdp_byte(8'(addr[7:0] + i), cfg.mem_bytes);
            default:    return peek(addr + i);
        endcase
    endfunction

    // cs_n rose: execute what the frame asked for (accepted = decision at decode)
    function void end_frame(odve_qspi_item tr, bit accepted, longint now);
        odve_qspi_fmt_t f = tr.fmt(cfg.bus.qpi_dummy);
        int unsigned    hdr = odve_qspi_hdr_clks(f);
        bit             exact = !tr.truncated && tr.partial_bits == 0;
        if (!accepted) begin n_ignored++; return; end
        update(now);
        case (tr.cmd)
            QSPI_WREN: if (tr.nclk >= hdr) wel = 1;
            QSPI_WRDI: if (tr.nclk >= hdr) wel = 0;
            QSPI_WRSR2: if (wel && exact && tr.wdata.size() == 1) begin
                qe = tr.wdata[0][1];
                start_op(now, cfg.tw);
            end
            QSPI_PP, QSPI_QPP: if (wel && exact && tr.wdata.size() > 0) begin
                bit [7:0] buf_ [int unsigned];
                int unsigned base = (tr.addr % cfg.mem_bytes) & ~32'hFF;
                foreach (tr.wdata[i]) buf_[(tr.addr[7:0] + i) % 256] = tr.wdata[i];
                foreach (buf_[k]) mem[base + k] = peek(base + k) & buf_[k];
                start_op(now, cfg.tpp);
            end
            QSPI_SE: if (wel && exact && tr.nclk == hdr) begin
                int unsigned base = (tr.addr % cfg.mem_bytes) & ~32'hFFF;
                for (int unsigned k = 0; k < 4096; k++) if (mem.exists(base + k)) mem.delete(base + k);
                start_op(now, cfg.tse);
            end
            default: ;
        endcase
        n_exec++;
    endfunction

    function void start_op(longint now, int unsigned t);
        busy_until = now + t;
        op_pending = 1;
    endfunction
endclass
