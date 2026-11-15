// RFFE slave (synthesizable RTL): NREG byte registers at addresses
// 0..NREG-1, answering to its Unique Slave ID `usid` and, for writes, to the
// broadcast USID 0. Commands: Register 0 Write, Register Write/Read,
// Extended Register Write/Read (8-bit address, 1..16 bytes, address wraps at
// 8 bits), Extended Register Write/Read Long (16-bit address, 1..8 bytes).
// Code 0001_xxxx (not supported here) and reads of the broadcast ID are
// ignored.
//
// Runs on the system clock `clk` and oversamples SCLK/SDATA (SCLK must stay
// at least two clocks in each phase): SCLK edges and the Sequence Start
// Condition (SDATA rising then falling while SCLK is low) are found by
// comparing with the previous sample. Write frames are sampled at SCLK
// falling edges; read data is driven one clock after SCLK rises.
//
// Parity (odd, every frame): a bad command or address frame ends the
// sequence for this slave (nothing written, no read data); a bad write data
// frame and the frames after it are dropped, the frames before it are
// written. Read data from an unimplemented register is an (actively driven)
// No Response Frame: nine zeros, parity included. A slave that is not
// addressed does not drive at all (passive NRF: the line stays parked at 0). SDATA has separate
// input, output and output enable; no tristate inside.
module dut #(
    parameter int NREG = 64              // a power of two, <= 256
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [3:0] usid,
    input  logic       sclk,
    input  logic       sdata_i,
    output logic       sdata_o,
    output logic       sdata_oe
);
    localparam int AW = $clog2(NREG);

    typedef enum logic [2:0] { S_IDLE, S_CMD, S_ADDR, S_WDATA, S_MBPC, S_RDATA, S_SBPC } st_e;

    st_e         st;
    logic        sclk_q, sdata_q, armed;
    logic [12:0] sh;
    logic [3:0]  bcnt;      // bits of the current frame so far
    logic [1:0]  acnt;      // address frames still to come
    logic [4:0]  ncnt;      // data frames still to come
    logic [15:0] addr;
    logic        wide;      // 16-bit address (long commands)
    logic        is_rd;
    logic [8:0]  rframe;
    logic [7:0]  regs [NREG];

    wire        rise  = sclk & ~sclk_q;
    wire        fall  = ~sclk & sclk_q;
    wire        ssc_r = ~sclk & ~sclk_q & sdata_i & ~sdata_q;
    wire        ssc_f = ~sclk & ~sclk_q & ~sdata_i & sdata_q;
    wire [12:0] shn   = {sh[11:0], sdata_i};          // the shift register with the bit sampled now
    wire        fr_ok = ^shn[8:0];                    // odd parity of a 9-bit frame
    wire [7:0]  c     = shn[8:1];                     // command field, when the command frame completes
    wire        c_rd  = (c[7:5] == 3'b011) || (c[7:4] == 4'b0010) || (c[7:3] == 5'b00111);
    wire        hit   = (shn[12:9] == usid) || (shn[12:9] == 4'h0 && !c_rd);
    wire        impl  = (addr < 16'(NREG));
    wire [15:0] addr_n = wide ? addr + 16'd1 : {8'h00, addr[7:0] + 8'd1};
    wire [7:0]  rbyte = impl ? regs[addr[AW-1:0]] : 8'h00;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= S_IDLE;
            sclk_q   <= 1'b0;
            sdata_q  <= 1'b0;
            armed    <= 1'b0;
            sh       <= '0;
            bcnt     <= '0;
            acnt     <= '0;
            ncnt     <= '0;
            addr     <= '0;
            wide     <= 1'b0;
            is_rd    <= 1'b0;
            rframe   <= '0;
            sdata_o  <= 1'b0;
            sdata_oe <= 1'b0;
            for (int i = 0; i < NREG; i++) regs[i] <= '0;
        end else begin
            sclk_q  <= sclk;
            sdata_q <= sdata_i;
            if (rise)       armed <= 1'b0;
            else if (ssc_r) armed <= 1'b1;

            if (ssc_f && armed) begin                    // Sequence Start Condition
                armed    <= 1'b0;
                st       <= S_CMD;
                bcnt     <= '0;
                sh       <= '0;
                sdata_oe <= 1'b0;
            end else begin
                case (st)
                    S_CMD: if (fall) begin
                        sh   <= shn;
                        bcnt <= bcnt + 4'd1;
                        if (bcnt == 4'd12) begin
                            bcnt <= '0;
                            addr <= '0;
                            wide <= 1'b0;
                            st   <= S_IDLE;
                            if (^shn && hit) begin
                                if (c[7]) begin                              // Register 0 Write
                                    regs[0] <= {1'b0, c[6:0]};
                                end else if (c[7:6] == 2'b01) begin          // Register Write / Read
                                    addr  <= {11'h0, c[4:0]};
                                    ncnt  <= 5'd1;
                                    is_rd <= c[5];
                                    st    <= c[5] ? S_MBPC : S_WDATA;
                                end else if (c[7:4] == 4'b0000 || c[7:4] == 4'b0010) begin   // Extended
                                    ncnt  <= {1'b0, c[3:0]} + 5'd1;
                                    is_rd <= c[5];
                                    acnt  <= 2'd1;
                                    st    <= S_ADDR;
                                end else if (c[7:4] == 4'b0011) begin        // Extended Long
                                    ncnt  <= {2'b00, c[2:0]} + 5'd1;
                                    is_rd <= c[3];
                                    wide  <= 1'b1;
                                    acnt  <= 2'd2;
                                    st    <= S_ADDR;
                                end
                            end
                        end
                    end
                    S_ADDR: if (fall) begin
                        sh   <= shn;
                        bcnt <= bcnt + 4'd1;
                        if (bcnt == 4'd8) begin
                            bcnt <= '0;
                            if (!fr_ok) st <= S_IDLE;
                            else begin
                                addr <= {addr[7:0], shn[8:1]};
                                acnt <= acnt - 2'd1;
                                if (acnt == 2'd1) st <= is_rd ? S_MBPC : S_WDATA;
                            end
                        end
                    end
                    S_WDATA: if (fall) begin
                        sh   <= shn;
                        bcnt <= bcnt + 4'd1;
                        if (bcnt == 4'd8) begin
                            bcnt <= '0;
                            if (!fr_ok) st <= S_IDLE;
                            else begin
                                if (impl) regs[addr[AW-1:0]] <= shn[8:1];
                                addr <= addr_n;
                                ncnt <= ncnt - 5'd1;
                                if (ncnt == 5'd1) st <= S_IDLE;
                            end
                        end
                    end
                    S_MBPC: if (fall) begin                      // the master's bus park: then we drive
                        st   <= S_RDATA;
                        bcnt <= '0;
                    end
                    S_RDATA: if (rise) begin
                        sdata_oe <= 1'b1;
                        if (bcnt == 4'd0) begin
                            rframe   <= impl ? {rbyte, ~^rbyte} : 9'h000;   // NRF: all zero, parity too
                            sdata_o  <= rbyte[7];
                        end else begin
                            sdata_o  <= rframe[4'd8 - bcnt];
                        end
                        bcnt <= bcnt + 4'd1;
                        if (bcnt == 4'd8) begin
                            bcnt <= '0;
                            addr <= addr_n;
                            ncnt <= ncnt - 5'd1;
                            if (ncnt == 5'd1) st <= S_SBPC;
                        end
                    end
                    S_SBPC: begin                                // our bus park cycle
                        if (rise) begin
                            sdata_oe <= 1'b1;
                            sdata_o  <= 1'b0;
                            bcnt     <= 4'd1;
                        end else if (fall && bcnt == 4'd1) begin
                            sdata_oe <= 1'b0;
                            st       <= S_IDLE;
                        end
                    end
                    default: st <= S_IDLE;
                endcase
            end
        end
    end
endmodule
