// The register file the slave agent plays (both slave modes use it: the
// driver in MEM mode, the responding sequence in SEQ mode). It speaks the
// same command protocol as the RTL slave in vrf/dut, so either can stand in
// for the other:
//
//   word 0 (master -> slave)  bit [word_bits-1] = 1 read / 0 write,
//                             bits [5:0] = start byte address (nbytes = 64)
//   word 0 (slave -> master)  the slave's ID byte, replicated over the word
//   words 1.. write           data, byte k of a word = bits [8k+7:8k] goes to
//                             address ptr+k; ptr advances by word_bits/8 and
//                             wraps at nbytes
//   words 1.. read            the same bytes, slave -> master
//
// A word cut short by cs_n rising is dropped. A non-multiple-of-8 width
// moves ceil(bits/8) bytes per word, the top byte truncated.
class odve_spi_slv_model extends uvm_object;
    `uvm_object_utils(odve_spi_slv_model)

    bit [7:0]    id     = 8'hA5;
    int unsigned nbytes = 64;
    bit [7:0]    mem [int unsigned];
    // frame state
    bit          rd;
    int unsigned ptr;
    int unsigned nrx;     // words received in this frame

    function new(string name = "odve_spi_slv_model");
        super.new(name);
    endfunction

    static function int unsigned bytes_per_word(int unsigned bits);
        return (bits + 7) / 8;
    endfunction

    function void start_frame();
        rd = 0; ptr = 0; nrx = 0;
    endfunction

    function bit [7:0] peek(int unsigned a);
        a = a % nbytes;
        return mem.exists(a) ? mem[a] : 8'h00;
    endfunction

    // the word the slave sends as word n of the frame
    function bit [31:0] tx_word(int unsigned n, int unsigned bits);
        bit [31:0] w = '0;
        if (n == 0) w = {4{id}};
        else if (rd)
            for (int k = 0; k < bytes_per_word(bits); k++) w[8*k +: 8] = peek(ptr + k);
        return (bits >= 32) ? w : (w & ((32'h1 << bits) - 1));
    endfunction

    // word n has been received completely
    function void rx_word(bit [31:0] w, int unsigned bits);
        int unsigned b = bytes_per_word(bits);
        if (nrx == 0) begin
            rd  = w[bits-1];
            ptr = w[5:0] % nbytes;
        end else begin
            if (!rd) for (int k = 0; k < b; k++) mem[(ptr + k) % nbytes] = w[8*k +: 8];
            ptr = (ptr + b) % nbytes;
        end
        nrx++;
    endfunction
endclass
