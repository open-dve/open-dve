// One SPI frame: everything between a chip select falling and rising. The bus
// is full duplex, so a frame carries a word stream in each direction; the
// word width, clock mode and bit order are properties of the selected slave
// (odve_spi_dev_cfg in the agent's cfg), copied here by the driver/monitor.
//
// No `rand`/constraints (ModelSim SE has no solver, comp/agents/README.md):
// user_randomize(), reached through `odve_rand(item), draws from the item's
// odve_rand stream `rng` - set it to a spawn() of the sequence's stream
// (comp/common/rand/README rule 3); without one the item makes its own.
class odve_spi_item extends uvm_sequence_item;
    `uvm_object_utils(odve_spi_item)

    // --- the frame
    int unsigned cs;                  // chip select index
    bit [31:0]   mosi[$];             // words master -> slave (word_bits wide, right aligned)
    bit [31:0]   miso[$];             // words slave -> master: filled by the master driver / the monitor
    // --- format of the selected slave (copied from cfg by driver/monitor)
    int unsigned word_bits = 8;
    bit          cpol, cpha, lsb_first;
    // --- master timing, in system clock cycles (-1: the cfg default)
    int          lead     = -1;       // cs_n fall -> first sclk edge          (block guide tL)
    int          trail    = -1;       // last sclk edge -> cs_n rise           (tT)
    int          idle     = -1;       // min cs_n high time before this frame  (tI)
    int unsigned word_gap = 0;        // extra idle sclk cycles between words under one cs_n
    int          abort_after_bits = -1;  // >= 0: raise cs_n after this many bits (inject an abort)
    bit          cpol_err = 0;        // inject: one extra sclk edge so cs_n rises with sclk off its idle level
    // --- monitor's view
    int unsigned partial_bits = 0;    // bits of an incomplete last word (cs_n rose mid-word)
    bit [31:0]   partial_mosi;        // that incomplete word, as far as it got (right aligned)
    bit          had_gap  = 0;        // an inter-word pause longer than a bit period was seen
    bit          proto_err = 0;       // the monitor reported a protocol/timing violation in this frame
    int unsigned half_period = 0;     // measured sclk half period (cycles)
    // --- reactive slave's request to its sequence (slave driver, SEQ mode)
    bit          frame_end = 0;       // cs_n rose: mosi holds the whole frame, no word to send

    // --- user_randomize knobs
    odve_rand    rng;
    int unsigned ncs        = 1;      // cs drawn from [0:ncs-1]
    int unsigned max_words  = 8;      // number of words drawn from [1:max_words]
    int unsigned gap_pct    = 0;      // chance of a non-zero word_gap

    function new(string name = "odve_spi_item");
        super.new(name);
    endfunction

    function bit [31:0] mask();
        return (word_bits >= 32) ? 32'hFFFF_FFFF : ((32'h1 << word_bits) - 1);
    endfunction

    function void user_randomize();
        int unsigned n;
        if (rng == null) rng = new(get_full_name());
        cs = rng.below(ncs);
        n  = rng.urand(1, max_words);
        mosi.delete();
        miso.delete();
        repeat (n) begin
            bit [31:0] w = rng.u32();
            mosi.push_back(w & mask());
        end
        word_gap = rng.chance(gap_pct) ? rng.urand(1, 6) : 0;
    endfunction

    function string convert2string();
        string s = $sformatf("cs%0d mode%0d %0db %s mosi=[", cs, {cpol, cpha}, word_bits, lsb_first ? "LSB" : "MSB");
        foreach (mosi[i]) s = {s, $sformatf("%s%0h", i ? " " : "", mosi[i])};
        s = {s, "] miso=["};
        foreach (miso[i]) s = {s, $sformatf("%s%0h", i ? " " : "", miso[i])};
        s = {s, "]"};
        if (partial_bits) s = {s, $sformatf(" ABORT+%0db", partial_bits)};
        if (proto_err)    s = {s, " PROTO_ERR"};
        return s;
    endfunction
endclass
