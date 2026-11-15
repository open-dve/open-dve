// I2S audio pipeline: receiver on port A -> processing -> transmitter on
// port B. Synthesizable RTL on one system clock `clk`; SCK/WS/SD are
// oversampled (2-flop synchronisers + edge detection) when the port is a
// clock target, or generated from `clk` when it is the clock controller.
//
// Processing (what the scoreboard predicts): channel swap + negation with
// saturation, slot k of the output frame = -(slot k^1 of the input frame),
// in word_len-bit two's complement, -full scale -> +full scale.
// I.e. stereo: out.L = -in.R, out.R = -in.L; TDM: pairs of slots swapped.
//
// One frame of buffering: a received frame is processed into `obuf`, and
// the transmitter takes it at the start of its next frame window. With no
// new frame the transmitter sends an all-zero (idle) frame; a frame that
// arrives while obuf is still full overwrites it (cnt_overrun).
//
// Static configuration (held during a run, the same for both ports):
//   cfg_fmt        0 I2S, 1 left-justified, 2 right-justified, 3 TDM
//   cfg_wlen       word length 16, 24 or 32
//   cfg_slot32     slot of 32 SCK periods (else 16)
//   cfg_nslots     slots per frame: 2 (I2S/LJ/RJ), 2/4/8 (TDM)
//   cfg_rx_master  port A: the DUT generates SCK/WS (receiver = controller)
//   cfg_tx_master  port B: the DUT generates SCK/WS (transmitter = controller)
//   cfg_half       controller SCK half period, in clk cycles (>= 4)
module dut (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [1:0]  cfg_fmt,
    input  logic [5:0]  cfg_wlen,
    input  logic        cfg_slot32,
    input  logic [3:0]  cfg_nslots,
    input  logic        cfg_rx_master,
    input  logic        cfg_tx_master,
    input  logic [7:0]  cfg_half,
    // port A: receiver
    input  logic        a_sck_i,
    input  logic        a_ws_i,
    input  logic        a_sd_i,
    output logic        a_sck_o,
    output logic        a_ws_o,
    output logic        a_clk_oe,
    // port B: transmitter
    input  logic        b_sck_i,
    input  logic        b_ws_i,
    output logic        b_sck_o,
    output logic        b_ws_o,
    output logic        b_clk_oe,
    output logic        b_sd_o,
    output logic        b_sd_oe,
    // status
    output logic [15:0] cnt_rx,
    output logic [15:0] cnt_tx,
    output logic [15:0] cnt_overrun
);
    localparam int MS = 8;     // max slots

    logic [5:0] slen;
    logic [8:0] nbits;
    logic [5:0] dly;
    logic [5:0] off;
    assign slen  = cfg_slot32 ? 6'd32 : 6'd16;
    assign nbits = cfg_slot32 ? {cfg_nslots, 5'd0} : {1'b0, cfg_nslots, 4'd0};
    assign dly   = (cfg_fmt == 2'd0 || cfg_fmt == 2'd3) ? 6'd1 : 6'd0;
    assign off   = (cfg_fmt == 2'd2) ? (slen - cfg_wlen) : 6'd0;

    assign a_clk_oe = cfg_rx_master;
    assign b_clk_oe = cfg_tx_master;
    assign b_sd_oe  = 1'b1;

    // window position of a frame position: SCK periods since the first data bit
    function automatic logic [8:0] win(input logic [8:0] p, input logic [8:0] n, input logic [5:0] d);
        return (p >= {3'd0, d}) ? p - {3'd0, d} : p + n - {3'd0, d};
    endfunction

    function automatic logic [31:0] wmask(input logic [5:0] w);
        return (w >= 6'd32) ? 32'hFFFF_FFFF : ((32'h1 << w) - 32'h1);
    endfunction

    // -v in w-bit two's complement, saturating -full scale
    function automatic logic [31:0] negsat(input logic [31:0] v, input logic [5:0] w);
        logic [31:0] l, r;
        l = v << (6'd32 - w);
        r = (l == 32'h8000_0000) ? 32'h7FFF_FFFF : (~l + 32'h1);
        return r >> (6'd32 - w);
    endfunction

    // ---------------------------------------------------------------- port A
    logic       a_fall, a_rise_d, a_synced, a_sd_d, a_drop;
    logic [8:0] a_pos;
    dut_i2s_port port_a (
        .clk(clk), .rst_n(rst_n), .master(cfg_rx_master), .half(cfg_half),
        .fmt(cfg_fmt), .slen(slen), .nbits(nbits),
        .sck_i(a_sck_i), .ws_i(a_ws_i), .sd_i(a_sd_i),
        .sck_o(a_sck_o), .ws_o(a_ws_o),
        .fall(a_fall), .rise_d(a_rise_d), .pos(a_pos), .synced(a_synced), .sd_d(a_sd_d), .drop(a_drop)
    );

    logic [31:0] rwords [MS];
    logic        win_ok, rx_done;
    logic [8:0]  ru;
    logic [5:0]  ri;
    logic [3:0]  rslot;
    assign ru    = win(a_pos, nbits, dly);
    assign ri    = cfg_slot32 ? {1'b0, ru[4:0]} : {2'b0, ru[3:0]};
    assign rslot = cfg_slot32 ? ru[8:5] : ru[7:4];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            win_ok  <= 1'b0;
            rx_done <= 1'b0;
            for (int k = 0; k < MS; k++) rwords[k] <= '0;
        end else begin
            rx_done <= 1'b0;
            if (a_rise_d) begin
                // a broken frame is dropped; a frame start that broke the
                // previous frame (drop with ru == 0) still opens the next one
                if (!a_synced || (a_drop && ru != 9'd0)) begin
                    win_ok <= 1'b0;
                end else if (ru == 9'd0 || win_ok) begin
                    win_ok <= 1'b1;
                    if (ri >= off && ri < off + cfg_wlen)
                        rwords[rslot[2:0]] <= {rwords[rslot[2:0]][30:0], a_sd_d};
                    if (ru == nbits - 9'd1) rx_done <= 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------- processing + buffer
    logic [31:0] obuf [MS];
    logic        obuf_valid, tx_load;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            obuf_valid  <= 1'b0;
            cnt_rx      <= '0;
            cnt_overrun <= '0;
            for (int k = 0; k < MS; k++) obuf[k] <= '0;
        end else if (rx_done) begin
            for (int k = 0; k < MS; k++)
                obuf[k] <= negsat(rwords[k ^ 1] & wmask(cfg_wlen), cfg_wlen);
            obuf_valid <= 1'b1;
            cnt_rx     <= cnt_rx + 16'd1;
            if (obuf_valid && !tx_load) cnt_overrun <= cnt_overrun + 16'd1;
        end else if (tx_load) begin
            obuf_valid <= 1'b0;
        end
    end

    // ---------------------------------------------------------------- port B
    logic       b_fall, b_rise_d, b_synced, b_sd_d, b_drop;
    logic [8:0] b_pos;
    dut_i2s_port port_b (
        .clk(clk), .rst_n(rst_n), .master(cfg_tx_master), .half(cfg_half),
        .fmt(cfg_fmt), .slen(slen), .nbits(nbits),
        .sck_i(b_sck_i), .ws_i(b_ws_i), .sd_i(1'b0),
        .sck_o(b_sck_o), .ws_o(b_ws_o),
        .fall(b_fall), .rise_d(b_rise_d), .pos(b_pos), .synced(b_synced), .sd_d(b_sd_d), .drop(b_drop)
    );

    logic [31:0] twords [MS];
    logic [31:0] tsrc   [MS];
    logic [8:0]  tq, tu;
    logic [5:0]  ti, tbit;
    logic [3:0]  tslot;
    assign tq    = (b_pos >= nbits - 9'd1) ? 9'd0 : b_pos + 9'd1;   // the period this falling edge starts
    assign tu    = win(tq, nbits, dly);
    assign ti    = cfg_slot32 ? {1'b0, tu[4:0]} : {2'b0, tu[3:0]};
    assign tslot = cfg_slot32 ? tu[8:5] : tu[7:4];
    assign tbit  = cfg_wlen - 6'd1 - (ti - off);
    assign tx_load = b_fall && b_synced && tu == 9'd0;
    always_comb begin
        for (int k = 0; k < MS; k++)
            tsrc[k] = (tu != 9'd0) ? twords[k] : (obuf_valid ? obuf[k] : 32'h0);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_sd_o <= 1'b0;
            cnt_tx <= '0;
            for (int k = 0; k < MS; k++) twords[k] <= '0;
        end else if (b_fall) begin
            if (!b_synced) begin
                b_sd_o <= 1'b0;
            end else begin
                if (tu == 9'd0) begin
                    for (int k = 0; k < MS; k++) twords[k] <= tsrc[k];
                    if (obuf_valid) cnt_tx <= cnt_tx + 16'd1;
                end
                b_sd_o <= (ti >= off && ti < off + cfg_wlen) ? tsrc[tslot[2:0]][tbit[4:0]] : 1'b0;
            end
        end
    end

    logic unused;
    assign unused = b_sd_d | b_rise_d | b_drop;
endmodule

// One I2S port's clocking: controller (SCK/WS generated from clk) or target
// (SCK/WS/SD synchronised, edges detected, frame position tracked from WS
// with the same checks as the agent's monitor: wrong frame length, WS at
// the wrong level -> drop the frame in progress and resynchronise).
//   fall    strobe, the clk cycle SCK falls: SCK period pos+1 begins
//   rise_d  strobe, one clk after SCK rose: pos is the period just sampled,
//           sd_d its SD bit, drop = that period broke the frame
module dut_i2s_port (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       master,
    input  logic [7:0] half,
    input  logic [1:0] fmt,
    input  logic [5:0] slen,
    input  logic [8:0] nbits,
    input  logic       sck_i,
    input  logic       ws_i,
    input  logic       sd_i,
    output logic       sck_o,
    output logic       ws_o,
    output logic       fall,
    output logic       rise_d,
    output logic [8:0] pos,
    output logic       synced,
    output logic       sd_d,
    output logic       drop
);
    logic ws_first;
    assign ws_first = (fmt != 2'd0);    // I2S: left (WS low) first; LJ/RJ: WS high first; TDM: pulse high

    function automatic logic ws_of(input logic [8:0] p, input logic [1:0] f, input logic [5:0] s, input logic first);
        if (f == 2'd3) return (p == 9'd0);
        return (p < {3'd0, s}) ? first : !first;
    endfunction

    // synchronisers
    logic sck_s1, sck_s2, sck_s3, ws_s1, ws_s2, sd_s1, sd_s2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {sck_s1, sck_s2, sck_s3} <= 3'b111;
            {ws_s1, ws_s2, sd_s1, sd_s2} <= 4'b0;
        end else begin
            sck_s1 <= sck_i; sck_s2 <= sck_s1; sck_s3 <= sck_s2;
            ws_s1  <= ws_i;  ws_s2  <= ws_s1;
            sd_s1  <= sd_i;  sd_s2  <= sd_s1;
        end
    end

    // controller
    logic [7:0] cnt;
    logic [8:0] mpos;
    logic       m_tick, m_rise, m_fall;
    assign m_tick = master && (cnt >= half - 8'd1);
    assign m_rise = m_tick && !sck_o;
    assign m_fall = m_tick && sck_o;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= '0;
            sck_o    <= 1'b1;
            ws_o     <= ws_of(nbits - 9'd1, fmt, slen, ws_first);
            mpos     <= nbits - 9'd1;
        end else if (master) begin
            if (m_tick) begin
                cnt   <= '0;
                sck_o <= !sck_o;
                if (m_fall) begin
                    mpos     <= (mpos >= nbits - 9'd1) ? 9'd0 : mpos + 9'd1;
                    ws_o     <= ws_of((mpos >= nbits - 9'd1) ? 9'd0 : mpos + 9'd1, fmt, slen, ws_first);
                end
            end else begin
                cnt <= cnt + 8'd1;
            end
        end
    end

    // target
    logic       s_rise, s_fall, prev_ok, prev_ws, t_synced, start, miss, wsbad, len_err;
    logic [8:0] tpos, p_next;
    assign s_rise  = !master && sck_s2 && !sck_s3;
    assign s_fall  = !master && !sck_s2 && sck_s3;
    assign start   = prev_ok && (prev_ws == !ws_first) && (ws_s2 == ws_first);
    assign p_next  = start ? 9'd0 : tpos + 9'd1;
    assign len_err = start && t_synced && (tpos != nbits - 9'd1);
    assign miss    = !start && t_synced && (tpos + 9'd1 >= nbits);
    assign wsbad   = (start || t_synced) && (ws_s2 != ws_of(p_next, fmt, slen, ws_first));
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_ok  <= 1'b0;
            prev_ws  <= 1'b0;
            t_synced <= 1'b0;
            tpos     <= '0;
        end else if (s_rise) begin
            prev_ok  <= 1'b1;
            prev_ws  <= ws_s2;
            tpos     <= (p_next >= nbits) ? 9'd0 : p_next;
            t_synced <= (start || t_synced) && !miss && !wsbad;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rise_d <= 1'b0;
            sd_d   <= 1'b0;
            drop   <= 1'b0;
        end else begin
            rise_d <= m_rise || s_rise;
            if (m_rise || s_rise) begin
                sd_d <= sd_s2;
                drop <= s_rise && (len_err || miss || wsbad);
            end
        end
    end

    assign fall   = master ? m_fall : s_fall;
    assign pos    = master ? mpos : tpos;
    assign synced = master ? 1'b1 : t_synced;     // a controller knows its own frame position
endmodule
