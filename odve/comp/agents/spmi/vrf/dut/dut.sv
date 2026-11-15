// SPMI slave (synthesizable RTL) answering to its Slave ID `sid`:
//   0x00..NREG-1  read/write byte registers (Register 0 Write sets reg 0 to {0, D[6:0]})
//   NREG (0x40)   read-only power state: 0 ACTIVE, 1 SLEEP, 2 SHUTDOWN
//   above         writes ignored, reads answered with a No Response Frame
// Commands: Register 0 Write, Register Write/Read (5-bit address), Extended
// Register Write/Read (8-bit address, 1..16 bytes, address wraps at 8 bits),
// Extended Register Write/Read Long (16-bit address, 1..8 bytes), Reset
// (clears the registers, state ACTIVE), Sleep, Shutdown, Wakeup (state
// only - the slave keeps answering in every state). Other codes are ignored.
//
// Runs on the system clock `clk` and oversamples SCLK/SDATA (SCLK must stay
// at least two clocks in each phase): SCLK edges and the Sequence Start
// Condition (SDATA rising then falling while SCLK is low) are found by
// comparing with the previous sample. Master frames are sampled at SCLK
// falling edges; read data, ACK/NACK and bus park are driven one clock after
// SCLK rises.
//
// Every non-read command is answered with the ACK/NACK bit after the
// master's bus park: 1 (ACK) when every frame had good parity, 0 (NACK)
// after a bad address or data frame of a write (bad address: nothing
// written; bad data frame: it and the following frames dropped, earlier
// ones written). A bad command frame, or a bad address frame of a read, ends
// the sequence for this slave: it does not drive at all. Read data from an
// unimplemented register is a No Response Frame (nine zeros, parity too).
// SDATA has separate input, output and output enable; no tristate inside.
module dut #(
    parameter int NREG = 64              // a power of two, <= 128
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [3:0] sid,
    input  logic       sclk,
    input  logic       sdata_i,
    output logic       sdata_o,
    output logic       sdata_oe,
    output logic [1:0] pm_state
);
    localparam int AW = $clog2(NREG);

    typedef enum logic [3:0] { S_IDLE, S_CMD, S_ADDR, S_WDATA, S_MBPC, S_RDATA, S_WBPC, S_ACK, S_SBPC } st_e;

    st_e         st;
    logic        sclk_q, sdata_q, armed;
    logic [12:0] sh;
    logic [3:0]  bcnt;      // bits of the current frame so far
    logic [1:0]  acnt;      // address frames still to come
    logic [4:0]  ncnt;      // data frames still to come
    logic [15:0] addr;
    logic        wide;      // 16-bit address (long commands)
    logic        is_rd;
    logic        drop;      // a bad address/data frame: write nothing more, NACK
    logic [8:0]  rframe;
    logic [7:0]  regs [NREG];

    wire        rise  = sclk & ~sclk_q;
    wire        fall  = ~sclk & sclk_q;
    wire        ssc_r = ~sclk & ~sclk_q & sdata_i & ~sdata_q;
    wire        ssc_f = ~sclk & ~sclk_q & ~sdata_i & sdata_q;
    wire [12:0] shn   = {sh[11:0], sdata_i};          // the shift register with the bit sampled now
    wire        fr_ok = ^shn[8:0];                    // odd parity of a 9-bit frame
    wire [7:0]  c     = shn[8:1];                     // command field, when the command frame completes
    wire        impl  = (addr < 16'(NREG));
    wire        is_pm = (addr == 16'(NREG));
    wire [15:0] addr_n = wide ? addr + 16'd1 : {8'h00, addr[7:0] + 8'd1};
    wire [7:0]  rbyte = impl ? regs[addr[AW-1:0]] : is_pm ? {6'h00, pm_state} : 8'h00;

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
            drop     <= 1'b0;
            rframe   <= '0;
            sdata_o  <= 1'b0;
            sdata_oe <= 1'b0;
            pm_state <= 2'd0;
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
                drop     <= 1'b0;
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
                            if (^shn && shn[12:9] == sid) begin
                                if (c[7]) begin                              // Register 0 Write
                                    regs[0] <= {1'b0, c[6:0]};
                                    st      <= S_WBPC;
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
                                end else if (c[7:2] == 6'b000100) begin      // Reset / Sleep / Shutdown / Wakeup
                                    case (c[1:0])
                                        2'd0: begin
                                            for (int i = 0; i < NREG; i++) regs[i] <= '0;
                                            pm_state <= 2'd0;
                                        end
                                        2'd1:    pm_state <= 2'd1;
                                        2'd2:    pm_state <= 2'd2;
                                        default: pm_state <= 2'd0;
                                    endcase
                                    st <= S_WBPC;
                                end
                            end
                        end
                    end
                    S_ADDR: if (fall) begin
                        sh   <= shn;
                        bcnt <= bcnt + 4'd1;
                        if (bcnt == 4'd8) begin
                            bcnt <= '0;
                            addr <= {addr[7:0], shn[8:1]};
                            acnt <= acnt - 2'd1;
                            if (!fr_ok) drop <= 1'b1;
                            if (!fr_ok && is_rd)  st <= S_IDLE;
                            else if (acnt == 2'd1) st <= is_rd ? S_MBPC : S_WDATA;
                        end
                    end
                    S_WDATA: if (fall) begin
                        sh   <= shn;
                        bcnt <= bcnt + 4'd1;
                        if (bcnt == 4'd8) begin
                            bcnt <= '0;
                            if (!fr_ok) drop <= 1'b1;
                            else if (!drop && impl) regs[addr[AW-1:0]] <= shn[8:1];
                            addr <= addr_n;
                            ncnt <= ncnt - 5'd1;
                            if (ncnt == 5'd1) st <= S_WBPC;
                        end
                    end
                    S_MBPC: if (fall) begin                      // the master's bus park: then we drive
                        st   <= S_RDATA;
                        bcnt <= '0;
                    end
                    S_RDATA: if (rise) begin
                        sdata_oe <= 1'b1;
                        if (bcnt == 4'd0) begin
                            rframe  <= (impl || is_pm) ? {rbyte, ~^rbyte} : 9'h000;   // NRF: all zero, parity too
                            sdata_o <= rbyte[7];
                        end else begin
                            sdata_o <= rframe[4'd8 - bcnt];
                        end
                        bcnt <= bcnt + 4'd1;
                        if (bcnt == 4'd8) begin
                            bcnt <= '0;
                            addr <= addr_n;
                            ncnt <= ncnt - 5'd1;
                            if (ncnt == 5'd1) st <= S_SBPC;
                        end
                    end
                    S_WBPC: if (fall) st <= S_ACK;              // the master's bus park after a write / PM command
                    S_ACK: if (rise) begin                       // ACK/NACK
                        sdata_oe <= 1'b1;
                        sdata_o  <= ~drop;
                        bcnt     <= '0;
                        st       <= S_SBPC;
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
