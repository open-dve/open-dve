// I2C target bit/byte layer, synthesizable (no delays, no classes).
//
// SCL/SDA are oversampled with the system clock through two-flop
// synchronizers; START/STOP and SCL edges are detected on the synchronized
// lines (so the order of SDA/SCL changes is preserved). The open-drain
// outputs are *_oe (1 = pull low); the caller ties *_o to 0.
//
// Byte interface to the device logic above it:
//   start_p/restart  START or repeated START seen
//   stop_p           STOP seen
//   abort_p          START/STOP inside a byte, or the clock-low timeout
//   tmo_p            SCL low for TMO_CYC cycles (TMO_CYC = 0: never) - the
//                    interface releases the bus and waits for a START
//   rx_p/rx_data     a byte was received (at its 8th SCL rise); rx_first =
//                    first byte after (r)START, i.e. an address byte.
//                    The device answers with rx_ack (and, for an address
//                    byte, rx_tx = become transmitter) by the SCL fall,
//                    i.e. registered on rx_p is in time.
//   tx_p             the next byte to transmit is needed; tx_data is
//                    sampled at the following SCL fall (register it on tx_p)
//   mack_p/mack      the controller's acknowledge of a transmitted byte
//   stretch_cyc      SCL is held low this many cycles after each
//                    acknowledge of a continuing transfer (clock stretching)
// Used by the i2c, smbus and pmbus DUTs.
module odve_i2c_tgt_phy #(
    parameter int unsigned TMO_CYC = 0
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       scl_i,
    input  logic       sda_i,
    output logic       scl_oe,
    output logic       sda_oe,
    output logic       start_p,
    output logic       restart,
    output logic       stop_p,
    output logic       abort_p,
    output logic       tmo_p,
    output logic       rx_p,
    output logic [7:0] rx_data,
    output logic       rx_first,
    input  logic       rx_ack,
    input  logic       rx_tx,
    output logic       tx_p,
    input  logic [7:0] tx_data,
    output logic       mack_p,
    output logic       mack,
    input  logic [7:0] stretch_cyc
);
    typedef enum logic [2:0] { P_IDLE, P_RX, P_RX_ACK, P_TX, P_TX_ACK, P_WAIT } pst_e;

    logic [2:0]  scl_s, sda_s;
    logic        scl, scl_d, sda, sda_d;
    logic        scl_rise, scl_fall, start_c, stop_c;
    pst_e        st;
    logic        busy, first, inbyte, ack_q, tx_q;
    logic [3:0]  bitcnt;
    logic [7:0]  sh;
    logic [7:0]  str_cnt;
    logic [15:0] lowcnt;

    assign scl      = scl_s[1];
    assign scl_d    = scl_s[2];
    assign sda      = sda_s[1];
    assign sda_d    = sda_s[2];
    assign scl_rise = scl & ~scl_d;
    assign scl_fall = ~scl & scl_d;
    assign start_c  = scl & scl_d & sda_d & ~sda;
    assign stop_c   = scl & scl_d & ~sda_d & sda;

    wire in_byte_now = (st == P_RX && inbyte) || (st == P_TX && bitcnt != 4'd0);
    wire tmo_hit     = (TMO_CYC != 0) && busy && !scl && (lowcnt == 16'(TMO_CYC - 1));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_s <= 3'b111; sda_s <= 3'b111;
            scl_oe <= 1'b0; sda_oe <= 1'b0;
            start_p <= 1'b0; restart <= 1'b0; stop_p <= 1'b0; abort_p <= 1'b0; tmo_p <= 1'b0;
            rx_p <= 1'b0; rx_data <= 8'h00; rx_first <= 1'b0; tx_p <= 1'b0; mack_p <= 1'b0; mack <= 1'b0;
            st <= P_IDLE; busy <= 1'b0; first <= 1'b0; inbyte <= 1'b0; ack_q <= 1'b0; tx_q <= 1'b0;
            bitcnt <= 4'd0; sh <= 8'h00; str_cnt <= 8'h00; lowcnt <= 16'h0;
        end else begin
            scl_s <= {scl_s[1:0], scl_i};
            sda_s <= {sda_s[1:0], sda_i};
            start_p <= 1'b0; stop_p <= 1'b0; abort_p <= 1'b0; tmo_p <= 1'b0;
            rx_p <= 1'b0; tx_p <= 1'b0; mack_p <= 1'b0;

            if (str_cnt != 8'h00) begin
                str_cnt <= str_cnt - 8'h01;
                if (str_cnt == 8'h01) scl_oe <= 1'b0;
            end
            if (busy && !scl) lowcnt <= lowcnt + 16'h1;
            else              lowcnt <= 16'h0;

            if (tmo_hit) begin
                tmo_p <= 1'b1; abort_p <= 1'b1;
                busy <= 1'b0; st <= P_IDLE;
                scl_oe <= 1'b0; sda_oe <= 1'b0; str_cnt <= 8'h00;
            end else if (start_c) begin
                start_p <= 1'b1;
                restart <= busy;
                abort_p <= busy && in_byte_now;
                busy <= 1'b1; st <= P_RX; first <= 1'b1;
                bitcnt <= 4'd0; inbyte <= 1'b0;
                scl_oe <= 1'b0; sda_oe <= 1'b0; str_cnt <= 8'h00;
            end else if (stop_c) begin
                stop_p <= busy;
                abort_p <= busy && in_byte_now;
                busy <= 1'b0; st <= P_IDLE;
                scl_oe <= 1'b0; sda_oe <= 1'b0; str_cnt <= 8'h00;
            end else if (busy) begin
                case (st)
                    P_RX: begin
                        if (scl_rise) begin
                            sh <= {sh[6:0], sda};
                            bitcnt <= bitcnt + 4'd1;
                            if (bitcnt == 4'd7) begin
                                rx_p <= 1'b1;
                                rx_data <= {sh[6:0], sda};
                                rx_first <= first;
                            end
                        end
                        if (scl_fall) begin
                            if (bitcnt == 4'd8) begin
                                sda_oe <= rx_ack;
                                ack_q  <= rx_ack;
                                tx_q   <= first ? rx_tx : 1'b0;
                                tx_p   <= rx_ack && first && rx_tx;
                                first  <= 1'b0;
                                st <= P_RX_ACK;
                                bitcnt <= 4'd0;
                                inbyte <= 1'b0;
                            end else if (bitcnt != 4'd0) begin
                                inbyte <= 1'b1;
                            end
                        end
                    end
                    P_RX_ACK: if (scl_fall) begin
                        sda_oe <= 1'b0;
                        if (!ack_q) begin
                            st <= P_WAIT;
                        end else begin
                            if (tx_q) begin
                                sh <= tx_data;
                                sda_oe <= ~tx_data[7];
                                st <= P_TX;
                            end else begin
                                st <= P_RX;
                            end
                            bitcnt <= 4'd0;
                            if (stretch_cyc != 8'h00) begin
                                scl_oe <= 1'b1;
                                str_cnt <= stretch_cyc;
                            end
                        end
                    end
                    P_TX: if (scl_fall) begin
                        if (bitcnt == 4'd7) begin
                            sda_oe <= 1'b0;          // release for the controller's acknowledge
                            st <= P_TX_ACK;
                            bitcnt <= 4'd0;
                        end else begin
                            sda_oe <= ~sh[6];
                            sh <= {sh[6:0], 1'b0};
                            bitcnt <= bitcnt + 4'd1;
                        end
                    end
                    P_TX_ACK: begin
                        if (scl_rise) begin
                            mack_p <= 1'b1;
                            mack   <= ~sda;
                            ack_q  <= ~sda;
                            tx_p   <= ~sda;
                        end
                        if (scl_fall) begin
                            if (!ack_q) begin
                                st <= P_WAIT;
                            end else begin
                                sh <= tx_data;
                                sda_oe <= ~tx_data[7];
                                st <= P_TX;
                                bitcnt <= 4'd0;
                                if (stretch_cyc != 8'h00) begin
                                    scl_oe <= 1'b1;
                                    str_cnt <= stretch_cyc;
                                end
                            end
                        end
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
