// Reconstructs a QSPI frame from its rising sclk edges (the edges on which
// both sides sample, SPI mode 0 and 3 alike). Used by the monitor and the
// slave driver: start() at cs_n fall, rise(io) per rising edge, finish() at
// cs_n rise. Bit order on the lanes follows the datasheet's instruction
// tables: MSB first; with L lanes, clock j of a byte carries bits
// [7-j*L -: L] on IO[L-1:0] (IO3 = D7, ..., IO0 = D4 on the first quad clock);
// single-lane input is IO0 (DI), single-lane output IO1 (DO).
class odve_qspi_decoder extends uvm_object;
    `uvm_object_utils(odve_qspi_decoder)

    typedef enum { PH_CMD, PH_ADDR, PH_MODE, PH_DUMMY, PH_DATA, PH_NONE } phase_e;

    odve_qspi_item  tr;
    odve_qspi_fmt_t f;
    bit             known;           // opcode complete and valid
    int unsigned    rcnt;            // rising edges so far
    int unsigned    cmd_clks, a_end, m_end, hdr;
    int unsigned    qpi_dummy = 2;
    bit [7:0]       sh;              // data byte being assembled
    int unsigned    shn;             // its bits so far

    function new(string name = "odve_qspi_decoder");
        super.new(name);
    endfunction

    function void start(bit qpi, int unsigned qpi_dummy_ = 2);
        tr = odve_qspi_item::type_id::create("tr");
        tr.qpi = qpi;
        tr.cmd = '0;
        tr.addr = '0;
        tr.mode_byte = '0;
        tr.nrd = 0;
        qpi_dummy = qpi_dummy_;
        known = 0;
        rcnt = 0;
        cmd_clks = qpi ? 2 : 8;
        hdr = cmd_clks;
        sh = '0; shn = 0;
    endfunction

    // phase of rising edge k (valid once the opcode is known, k >= cmd_clks)
    function phase_e phase(int unsigned k);
        if (k < cmd_clks) return PH_CMD;
        if (!known)       return PH_NONE;
        if (k < a_end)    return PH_ADDR;
        if (k < m_end)    return PH_MODE;
        if (k < hdr)      return PH_DUMMY;
        return (f.data_lanes != 0) ? PH_DATA : PH_NONE;
    endfunction

    // lanes the master drives at rising edge k / the lanes carrying slave data
    function bit [3:0] master_lanes(int unsigned k);
        case (phase(k))
            PH_CMD:           return (cmd_clks == 2) ? 4'hF : 4'h1;
            PH_ADDR, PH_MODE: return (f.addr_lanes == 4) ? 4'hF : (f.addr_lanes == 2) ? 4'h3 : 4'h1;
            PH_DATA:          return f.data_out ? 4'h0 : (f.data_lanes == 4) ? 4'hF : (f.data_lanes == 2) ? 4'h3 : 4'h1;
            default:          return 4'h0;
        endcase
    endfunction
    function bit [3:0] slave_lanes(int unsigned k);
        if (phase(k) != PH_DATA || !f.data_out) return 4'h0;
        return (f.data_lanes == 4) ? 4'hF : (f.data_lanes == 2) ? 4'h3 : 4'h2;
    endfunction

    static function bit [3:0] lane_bits(bit [3:0] io, int unsigned lanes, bit dout);
        if (lanes == 1) return {3'b0, dout ? io[1] : io[0]};
        if (lanes == 2) return {2'b0, io[1:0]};
        return io;
    endfunction

    function void rise(bit [3:0] io);
        int unsigned k = rcnt;
        case (phase(k))
            PH_CMD: begin
                if (cmd_clks == 2) tr.cmd = {tr.cmd[3:0], io};
                else               tr.cmd = {tr.cmd[6:0], io[0]};
                if (k == cmd_clks - 1) begin
                    f = odve_qspi_fmt(tr.cmd, tr.qpi, qpi_dummy);
                    known = f.valid;
                    tr.unknown = !f.valid;
                    a_end = cmd_clks + (f.addr_lanes ? 24 / f.addr_lanes : 0);
                    m_end = a_end + f.mode_clks;
                    hdr   = m_end + f.dummy_clks;
                end
            end
            PH_ADDR: tr.addr      = (tr.addr << f.addr_lanes) | 24'(lane_bits(io, f.addr_lanes, 0));
            PH_MODE: tr.mode_byte = (tr.mode_byte << f.addr_lanes) | 8'(lane_bits(io, f.addr_lanes, 0));
            PH_DATA: begin
                sh  = (sh << f.data_lanes) | 8'(lane_bits(io, f.data_lanes, f.data_out));
                shn += f.data_lanes;
                if (shn == 8) begin
                    if (f.data_out) tr.rdata.push_back(sh);
                    else            tr.wdata.push_back(sh);
                    sh = '0; shn = 0;
                end
            end
            default: ;
        endcase
        rcnt++;
    endfunction

    // cs_n rose
    function odve_qspi_item finish();
        tr.nclk         = rcnt;
        tr.truncated    = (rcnt < hdr) || (rcnt < cmd_clks);
        tr.partial_bits = shn;
        if (known && f.data_out) tr.nrd = tr.rdata.size();
        return tr;
    endfunction
endclass
