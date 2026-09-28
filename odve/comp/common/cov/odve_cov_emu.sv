// Emulation backend of the functional-coverage store (doc/fcov-plan.md,
// phase 6b): the same flat bin layout as odve_cov_pkg::odve_cov_store, in
// synthesizable logic. N saturating W-bit counters take one hit per cycle
// on the sample port and are read back over APB3 - by host software on an
// emulator or FPGA, by the odve_apb_cov_emu_seq sequence in simulation -
// into the same cov.dump format, so covgen.py merges it like any other run.
//
// Address map (byte addresses, 32-bit words):
//   4*i               counter i, i < N            read: count, write: ignored
//   REG_BASE + 0      NSAMPLES  hits accepted      read only
//   REG_BASE + 4      N                            read only
//   REG_BASE + 8      W                            read only
//   REG_BASE + 12     CTRL  bit0 freeze (samples ignored while set),
//                           bit1 clear  (counters and NSAMPLES to 0, self-clearing)
//   anything else     pslverr
// REG_BASE sits at the top of a 64 KiB window so that N can grow without
// moving the registers. No wait states.
module odve_cov_emu #(
    parameter int unsigned N        = 8,               // counters (bins)
    parameter int unsigned W        = 1,               // bits per counter, saturating at all-ones
    parameter logic [31:0] REG_BASE = 32'h0000_FFF0
) (
    input  logic        clk,
    input  logic        rst_n,
    // sample port
    input  logic        smp_valid,
    input  logic [31:0] smp_idx,
    // APB3 slave
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic        pready,
    output logic [31:0] prdata,
    output logic        pslverr
);
    logic [W-1:0] cnt [N];
    logic [31:0]  nsamples;
    logic         freeze;

    wire [31:0] widx   = paddr >> 2;
    wire        is_cnt = widx < N;
    wire        is_reg = (paddr & 32'hFFFF_FFF0) == REG_BASE;
    wire [1:0]  rsel   = paddr[3:2];
    wire        access = psel & penable;
    wire        ctrl_wr = access & pwrite & is_reg & (rsel == 2'd3);

    assign pready  = 1'b1;
    assign pslverr = access & ~(is_cnt | is_reg);

    always_comb begin
        prdata = '0;
        if (is_cnt) begin
            for (int i = 0; i < N; i++)
                if (widx == 32'(i)) prdata = 32'(cnt[i]);
        end else if (is_reg) begin
            case (rsel)
                2'd0:    prdata = nsamples;
                2'd1:    prdata = 32'(N);
                2'd2:    prdata = 32'(W);
                default: prdata = {31'b0, freeze};
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N; i++) cnt[i] <= '0;
            nsamples <= '0;
            freeze   <= 1'b0;
        end else begin
            if (smp_valid && !freeze && smp_idx < N) begin
                for (int i = 0; i < N; i++)
                    if (smp_idx == 32'(i) && cnt[i] != {W{1'b1}}) cnt[i] <= cnt[i] + 1'b1;
                nsamples <= nsamples + 1;
            end
            if (ctrl_wr) begin                        // after the sample: a clear wins over a hit in the same cycle
                freeze <= pwdata[0];
                if (pwdata[1]) begin
                    for (int i = 0; i < N; i++) cnt[i] <= '0;
                    nsamples <= '0;
                end
            end
        end
    end
endmodule
