// SPI slave with a 64-byte register file, plain synthesizable RTL.
//
// The SPI lines are oversampled on the system clock through two-flop
// synchronizers (so sclk's half period must be >= 4 clk cycles: an edge is
// acted on 3 cycles after it happens, and MISO must be stable a cycle before
// the master samples it). The format comes from strap pins, sampled while
// deselected: cpol / cpha (the four SPI modes), lsb_first, wsel (0: 8-bit,
// 1: 16-bit, 2/3: 32-bit words). Words follow each other under one cs_n
// with or without idle sclk between them.
//
// Command protocol (frame = cs_n low ... high):
//   word 0 in    bit [W-1] = 1 read / 0 write, bits [5:0] = byte address
//   word 0 out   ID byte replicated over the word
//   words 1.. in   write: byte k of the word (bits [8k+7:8k]) -> reg[ptr+k]
//   words 1.. out  read:  reg[ptr+k] as byte k;  write: 0
//   ptr starts at the address and advances by W/8 per word, wrapping at 64.
// A word cut short by cs_n rising is discarded; MISO is driven (miso_oe)
// only while selected.
module dut #(
    parameter logic [7:0] ID = 8'hA5
) (
    input  logic       clk,
    input  logic       rst_n,
    // SPI
    input  logic       sclk,
    input  logic       mosi,
    input  logic       cs_n,
    output logic       miso,
    output logic       miso_oe,
    // format straps
    input  logic       cpol,
    input  logic       cpha,
    input  logic       lsb_first,
    input  logic [1:0] wsel
);
    localparam int NB = 64;

    logic [2:0]  sclk_q, cs_q;
    logic [1:0]  mosi_q;
    logic [7:0]  regs [NB];

    // format, latched while deselected
    logic        f_cpol, f_cpha, f_lsb;
    logic [5:0]  f_w;               // word width 8/16/32
    logic [2:0]  f_b;               // bytes per word

    // frame state
    logic [5:0]  bitc;              // bits of the current word received
    logic [31:0] rxw;               // current word being received
    logic [31:0] txw;               // current word being sent
    logic        first;             // word 0 not complete yet
    logic        rd;
    logic [5:0]  ptr;

    wire sclk_s = sclk_q[1], sclk_d = sclk_q[2];
    wire cs_s   = cs_q[1],   cs_d   = cs_q[2];
    wire mosi_s = mosi_q[1];
    wire active = !cs_s;
    wire edge_e = active && !cs_d && (sclk_s != sclk_d);
    wire leading = (sclk_s != f_cpol);
    wire smp_e  = edge_e && (leading ^ f_cpha);
    wire sft_e  = edge_e && !(leading ^ f_cpha);
    wire start  = active && cs_d;   // cs_n just fell

    // bit position of the i-th bit of a word in transmission order. Pure (all
    // inputs are arguments): it is also used in a continuous assignment.
    function automatic logic [5:0] bitpos(input logic lsb, input logic [5:0] w, input logic [5:0] i);
        return lsb ? i : (w - 6'd1 - i);
    endfunction
    function automatic logic [5:0] pos(input logic [5:0] i);
        return bitpos(f_lsb, f_w, i);
    endfunction

    // the word to send next (word 0: ID; read data words: registers at ptr)
    function automatic logic [31:0] tx_next(input logic is_first, input logic is_rd, input logic [5:0] p);
        logic [31:0] w;
        w = '0;
        if (is_first) w = {4{ID}};
        else if (is_rd)
            for (int k = 0; k < 4; k++)
                if (k < f_b) w[8*k +: 8] = regs[6'(p + 6'(k))];
        return w;
    endfunction

    wire [31:0] rx_full = rxw | ((32'h1 << bitpos(f_lsb, f_w, bitc)) & {32{mosi_s}});

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_q  <= '0;
            cs_q    <= '1;
            mosi_q  <= '0;
            f_cpol  <= 1'b0;
            f_cpha  <= 1'b0;
            f_lsb   <= 1'b0;
            f_w     <= 6'd8;
            f_b     <= 3'd1;
            bitc    <= '0;
            rxw     <= '0;
            txw     <= '0;
            first   <= 1'b1;
            rd      <= 1'b0;
            ptr     <= '0;
            miso    <= 1'b1;
            miso_oe <= 1'b0;
            for (int i = 0; i < NB; i++) regs[i] <= '0;
        end else begin
            sclk_q <= {sclk_q[1:0], sclk};
            cs_q   <= {cs_q[1:0], cs_n};
            mosi_q <= {mosi_q[0], mosi};

            if (!active) begin
                miso_oe <= 1'b0;
                f_cpol  <= cpol;
                f_cpha  <= cpha;
                f_lsb   <= lsb_first;
                f_w     <= (wsel == 2'd0) ? 6'd8 : (wsel == 2'd1) ? 6'd16 : 6'd32;
                f_b     <= (wsel == 2'd0) ? 3'd1 : (wsel == 2'd1) ? 3'd2  : 3'd4;
            end

            if (start) begin
                miso_oe <= 1'b1;
                bitc    <= '0;
                rxw     <= '0;
                first   <= 1'b1;
                rd      <= 1'b0;
                txw     <= {4{ID}};
                // CPHA=0: the first bit goes out with cs_n, before any edge
                if (!f_cpha) miso <= f_lsb ? ID[0] : ID[7];
            end else if (smp_e) begin
                if (bitc == f_w - 6'd1) begin            // word complete
                    bitc <= '0;
                    rxw  <= '0;
                    if (first) begin
                        first <= 1'b0;
                        rd    <= rx_full[f_w - 6'd1];
                        ptr   <= rx_full[5:0];
                    end else begin
                        if (!rd)
                            for (int k = 0; k < 4; k++)
                                if (k < f_b) regs[6'(ptr + 6'(k))] <= rx_full[8*k +: 8];
                        ptr <= ptr + 6'(f_b);
                    end
                end else begin
                    bitc <= bitc + 6'd1;
                    rxw  <= rx_full;
                end
            end else if (sft_e) begin
                if (bitc == '0) begin                    // start of a word: load it
                    logic [31:0] w;
                    w = tx_next(first, rd, ptr);         // first: only with CPHA=1 (CPHA=0 sent bit 0 at start)
                    txw  <= w;
                    miso <= w[pos('0)];
                end else begin
                    miso <= txw[pos(bitc)];
                end
            end
        end
    end

    initial $display("Hi from DUT: SPI slave, ID 0x%02h, %0d bytes", ID, NB);
endmodule
