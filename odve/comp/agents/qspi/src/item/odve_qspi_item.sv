// One QSPI frame (cs_n low ... high): an instruction, its address, mode
// bits, dummy clocks and data bytes, in the format odve_qspi_fmt() gives for
// the opcode and the bus mode (SPI or QPI).
//
// No `rand`/constraints (comp/agents/README.md): user_randomize(), reached
// through `odve_rand(item), draws address and write data from the item's
// odve_rand stream `rng` (a spawn() of the sequence's stream).
class odve_qspi_item extends uvm_sequence_item;
    `uvm_object_utils(odve_qspi_item)

    // --- the command
    bit [7:0]    cmd;
    bit          qpi;              // sent in QPI mode (copied from cfg by driver/monitor)
    bit [23:0]   addr;
    bit [7:0]    mode_byte = 8'h00; // M7-0 of BBh/EBh (M5-4 != 10: no continuous read mode)
    bit [7:0]    wdata[$];         // master -> slave data bytes
    bit [7:0]    rdata[$];         // slave -> master data bytes (master: filled; monitor: observed)
    int unsigned nrd = 1;          // master: data bytes to read
    // --- master injection knobs (system clock cycles, -1 = cfg)
    int          lead = -1, trail = -1, idle = -1;
    int          abort_after_clks = -1;   // >= 0: raise cs_n after this many sclk clocks
    int unsigned extra_clks = 0;          // clocks after the last bit, master lines released
    bit          cpol_err = 0;            // leave sclk off its idle level at cs_n rise
    // --- monitor's view
    int unsigned nclk;             // rising sclk edges in the frame
    int unsigned partial_bits;     // data bits of an incomplete last byte
    bit          truncated;        // cs_n rose before the data phase (or mid header)
    bit          unknown;          // opcode not valid in this mode
    bit          proto_err;        // the monitor reported a violation in this frame

    // --- reactive slave <-> its sequence (slave driver, SEQ mode)
    odve_qspi_slv_req_e slv_req = ODVE_QSPI_REQ_NONE;
    int unsigned idx;              // REQ_BYTE: index of the data byte wanted
    bit          ack;              // response to REQ_DECODE: the flash accepts the command
    longint      t_cyc;            // system clock cycle of the request (busy timing)

    // --- user_randomize knobs
    odve_rand    rng;
    int unsigned mem_bytes = 8192;
    int unsigned max_bytes = 16;

    function new(string name = "odve_qspi_item");
        super.new(name);
    endfunction

    function odve_qspi_fmt_t fmt(int unsigned qpi_dummy = 2);
        return odve_qspi_fmt(cmd, qpi, qpi_dummy);
    endfunction

    // address in the array, and data bytes for a write / count for a read
    function void user_randomize();
        int unsigned n;
        if (rng == null) rng = new(get_full_name());
        addr = rng.below(mem_bytes);
        n    = rng.urand(1, max_bytes);
        wdata.delete();
        repeat (n) begin
            bit [7:0] b = rng.urange(255);
            wdata.push_back(b);
        end
        nrd = rng.urand(1, max_bytes);
    endfunction

    function string convert2string();
        odve_qspi_fmt_t f = fmt();
        string s = $sformatf("%s %02h(%0d)", qpi ? "QPI" : "SPI", cmd, f.fmt_code);
        if (f.addr_lanes) s = {s, $sformatf(" @%06h", addr)};
        if (wdata.size()) s = {s, $sformatf(" wr%0d[%02h..]", wdata.size(), wdata[0])};
        if (rdata.size()) s = {s, $sformatf(" rd%0d[%02h..]", rdata.size(), rdata[0])};
        if (partial_bits) s = {s, $sformatf(" +%0db", partial_bits)};
        if (truncated)    s = {s, " TRUNC"};
        if (unknown)      s = {s, " UNKNOWN"};
        if (proto_err)    s = {s, " PROTO_ERR"};
        return s;
    endfunction
endclass
