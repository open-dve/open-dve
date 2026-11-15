// UART echo device: a 16550-style receiver and transmitter around an RX
// FIFO. Every character received without error is sent back on txd
// complemented (~data within the data bits), in the same frame format.
// Synthesizable RTL: no classes, no delays.
//
//   lcr[1:0]  word length 5..8 (16550 LCR bits 0-1)
//   lcr[2]    stop bits: 0 = 1, 1 = 1.5 with 5 data bits, else 2 (LCR bit 2)
//   lcr[3]    parity enable, lcr[4] even parity, lcr[5] stick parity (LCR 3-5)
//   div       clk cycles per 16x tick (>= 1): bit time = 16 * div clocks
//   afe       auto flow control: rts_n high while the FIFO holds DEPTH-1 or
//             more characters (auto-RTS); a character is started only while
//             cts_n is low (auto-CTS). afe = 0: rts_n low, cts_n ignored.
//
// Receiver: rxd synchronised by two flops, sampled on the 16x tick. A
// start bit is a space seen in idle and still space 8 ticks later (else a
// false start, ignored); then one sample per 16 ticks (bit middles); only
// the first stop bit is checked. Per character, on the stop-bit sample:
//   bi: data, parity and stop bit all space (pe = fe = 0)
//   fe: stop bit space (not a break); pe: wrong parity
//   either, or a good character arriving at a full FIFO (oe, character lost):
//   one-clock pulse on st_valid with the flags on st_oe/st_pe/st_fe/st_bi.
// Errored characters are not stored (and so not echoed). After a stop bit
// sampled as space the receiver waits for mark before looking for the next
// start bit.
module dut #(
    parameter int unsigned DEPTH = 8
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [5:0]  lcr,
    input  logic [15:0] div,
    input  logic        afe,
    input  logic        rxd,
    output logic        txd,
    input  logic        cts_n,
    output logic        rts_n,
    output logic        st_valid,
    output logic        st_oe,
    output logic        st_pe,
    output logic        st_fe,
    output logic        st_bi,
    output logic [$clog2(DEPTH+1)-1:0] rx_level
);
    localparam int unsigned AW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam int unsigned LW = $clog2(DEPTH+1);

    // ---------------------------------------------------------------- format
    logic [3:0] nbits;
    logic [7:0] mask;
    logic [5:0] stop_ticks;
    assign nbits      = 4'd5 + {2'b00, lcr[1:0]};
    assign mask       = 8'hFF >> (2'd3 - lcr[1:0]);
    assign stop_ticks = !lcr[2] ? 6'd16 : (lcr[1:0] == 2'b00) ? 6'd24 : 6'd32;

    function automatic logic par_bit(input logic [7:0] d, input logic [7:0] m, input logic [5:0] l);
        logic x;
        x = ^(d & m);
        if (l[5]) return ~l[4];            // stick: even-select 1 -> space, 0 -> mark
        return l[4] ? x : ~x;              // even / odd
    endfunction

    // ------------------------------------------------------------ 16x tick
    logic [15:0] tcnt;
    logic        tick;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tcnt <= '0;
            tick <= 1'b0;
        end else if (tcnt + 16'd1 >= div) begin
            tcnt <= '0;
            tick <= 1'b1;
        end else begin
            tcnt <= tcnt + 16'd1;
            tick <= 1'b0;
        end
    end

    // ------------------------------------------------------- synchronisers
    logic rx_s1, rx_s2, cts_s1, cts_s2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s1  <= 1'b1;
            rx_s2  <= 1'b1;
            cts_s1 <= 1'b1;
            cts_s2 <= 1'b1;
        end else begin
            rx_s1  <= rxd;
            rx_s2  <= rx_s1;
            cts_s1 <= cts_n;
            cts_s2 <= cts_s1;
        end
    end

    // ---------------------------------------------------------------- FIFO
    logic [7:0]    mem [DEPTH];
    logic [AW-1:0] wptr, rptr;
    logic [LW-1:0] count;
    logic          push, pop;
    logic [7:0]    push_data;
    assign rx_level = count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr  <= '0;
            rptr  <= '0;
            count <= '0;
        end else begin
            if (push) begin
                mem[wptr] <= push_data;
                wptr      <= (wptr == AW'(DEPTH - 1)) ? '0 : wptr + 1'b1;
            end
            if (pop) rptr <= (rptr == AW'(DEPTH - 1)) ? '0 : rptr + 1'b1;
            count <= count + LW'(push) - LW'(pop);
        end
    end

    // ------------------------------------------------------------ receiver
    typedef enum logic [2:0] { R_IDLE, R_START, R_DATA, R_PAR, R_STOP, R_MARK } rstate_e;
    rstate_e    rstate;
    logic [3:0] rcnt;
    logic [2:0] rbit;
    logic [7:0] rsh;
    logic       rpar;
    logic [7:0] rdat;
    logic       r_pe, r_bi, r_fe;
    assign rdat = rsh & mask;
    assign r_bi = !rx_s2 && (rdat == 8'h00) && (!lcr[3] || !rpar);
    assign r_fe = !rx_s2 && !r_bi;
    assign r_pe = !r_bi && lcr[3] && (rpar != par_bit(rdat, mask, lcr));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate    <= R_IDLE;
            rcnt      <= '0;
            rbit      <= '0;
            rsh       <= '0;
            rpar      <= 1'b0;
            push      <= 1'b0;
            push_data <= '0;
            st_valid  <= 1'b0;
            st_oe     <= 1'b0;
            st_pe     <= 1'b0;
            st_fe     <= 1'b0;
            st_bi     <= 1'b0;
        end else begin
            push     <= 1'b0;
            st_valid <= 1'b0;
            st_oe    <= 1'b0;
            st_pe    <= 1'b0;
            st_fe    <= 1'b0;
            st_bi    <= 1'b0;
            case (rstate)
                R_IDLE:
                    if (tick && !rx_s2) begin
                        rstate <= R_START;
                        rcnt   <= '0;
                        rsh    <= '0;
                        rpar   <= 1'b0;
                    end
                R_START:
                    if (tick) begin
                        if (rcnt == 4'd7) begin
                            rcnt <= '0;
                            rbit <= '0;
                            rstate <= rx_s2 ? R_IDLE : R_DATA;     // false start bit: back to idle
                        end else begin
                            rcnt <= rcnt + 4'd1;
                        end
                    end
                R_DATA:
                    if (tick) begin
                        rcnt <= rcnt + 4'd1;
                        if (rcnt == 4'd15) begin
                            rsh[rbit] <= rx_s2;
                            rbit      <= rbit + 3'd1;
                            if ({1'b0, rbit} == nbits - 4'd1) rstate <= lcr[3] ? R_PAR : R_STOP;
                        end
                    end
                R_PAR:
                    if (tick) begin
                        rcnt <= rcnt + 4'd1;
                        if (rcnt == 4'd15) begin
                            rpar   <= rx_s2;
                            rstate <= R_STOP;
                        end
                    end
                R_STOP:
                    if (tick) begin
                        rcnt <= rcnt + 4'd1;
                        if (rcnt == 4'd15) begin
                            if (r_bi || r_fe || r_pe) begin
                                st_valid <= 1'b1;
                                st_bi    <= r_bi;
                                st_fe    <= r_fe;
                                st_pe    <= r_pe;
                            end else if (count == LW'(DEPTH)) begin
                                st_valid <= 1'b1;
                                st_oe    <= 1'b1;
                            end else begin
                                push      <= 1'b1;
                                push_data <= rdat;
                            end
                            rstate <= rx_s2 ? R_IDLE : R_MARK;
                        end
                    end
                R_MARK:
                    if (rx_s2) rstate <= R_IDLE;
                default:
                    rstate <= R_IDLE;
            endcase
        end
    end

    // --------------------------------------------------------- transmitter
    typedef enum logic [1:0] { T_IDLE, T_DATA, T_PAR, T_STOP } tstate_e;
    tstate_e    tstate;
    logic [5:0] tcnt_t;
    logic [3:0] tbit;            // 0 = start bit, 1..nbits = data bits
    logic [7:0] tsh;
    logic       tpar;
    logic [7:0] tdat;
    assign tdat = ~mem[rptr] & mask;
    assign pop  = (tstate == T_IDLE) && tick && (count != '0) && (!afe || !cts_s2);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tstate <= T_IDLE;
            tcnt_t <= '0;
            tbit   <= '0;
            tsh    <= '0;
            tpar   <= 1'b0;
            txd    <= 1'b1;
        end else begin
            case (tstate)
                T_IDLE:
                    if (pop) begin
                        tsh    <= tdat;
                        tpar   <= par_bit(tdat, mask, lcr);
                        txd    <= 1'b0;                       // start bit
                        tbit   <= '0;
                        tcnt_t <= '0;
                        tstate <= T_DATA;
                    end
                T_DATA:
                    if (tick) begin
                        if (tcnt_t == 6'd15) begin
                            tcnt_t <= '0;
                            if (tbit == nbits) begin
                                if (lcr[3]) begin
                                    txd    <= tpar;
                                    tstate <= T_PAR;
                                end else begin
                                    txd    <= 1'b1;
                                    tstate <= T_STOP;
                                end
                            end else begin
                                txd  <= tsh[tbit[2:0]];
                                tbit <= tbit + 4'd1;
                            end
                        end else begin
                            tcnt_t <= tcnt_t + 6'd1;
                        end
                    end
                T_PAR:
                    if (tick) begin
                        if (tcnt_t == 6'd15) begin
                            tcnt_t <= '0;
                            txd    <= 1'b1;
                            tstate <= T_STOP;
                        end else begin
                            tcnt_t <= tcnt_t + 6'd1;
                        end
                    end
                T_STOP:
                    if (tick) begin
                        if (tcnt_t == stop_ticks - 6'd1) begin
                            tcnt_t <= '0;
                            tstate <= T_IDLE;
                        end else begin
                            tcnt_t <= tcnt_t + 6'd1;
                        end
                    end
                default:
                    tstate <= T_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------- auto-RTS
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rts_n <= 1'b1;
        else        rts_n <= afe && (count >= LW'(DEPTH - 1));
    end
endmodule
