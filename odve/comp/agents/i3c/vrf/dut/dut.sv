// I3C SDR target (RTL, synthesizable, one clock). What the agent is checked
// against when +i3c_target=dut|both (default dut).
//
//   - 48-bit Provisioned ID, BCR, DCR (parameters); Dynamic Address assigned
//     by ENTDAA (arbitration on the open-drain ID phase) or SETDASA (when
//     STATIC_ADDR != 0); RSTDAA clears it
//   - private write: first byte = register pointer, the following bytes are
//     written from there (auto-increment, wraps at NREG)
//   - private read: bytes from the pointer, auto-increment; the target ends
//     the read (T-bit 0) on the byte of register NREG-1, otherwise T=1 and the
//     controller decides (it may abort with a repeated START)
//   - write T-bit = odd parity; a wrong one sets the protocol-error status
//     bit (GETSTATUS[5], cleared by reading it) and the rest of the transfer
//     is ignored
//   - CCCs: broadcast ENEC/DISEC/RSTDAA/ENTDAA/SETMWL, direct ENEC/DISEC/
//     SETMWL/GETMWL/GETPID/GETBCR/GETDCR/GETSTATUS/SETDASA
//   - In-Band Interrupt: a pulse on ibi_req queues one IBI with Mandatory
//     Data Byte ibi_mdb. Sent when events are enabled (ENEC ENINT) and the
//     target has a dynamic address: by pulling SDA low after T_AVAL clocks of
//     idle bus (START request), or by arbitrating in the header after any
//     START. NACKed -> stays pending (GETSTATUS[3:0] = 1) and is retried.
//
// Bus timing: everything is sampled on clk; SCL edges are seen one clk
// later (scl_q). A target bit is driven on the clk after SCL falls and read
// on the clk after SCL rises - the controller agent keeps SCL low and high
// for several clks, so this is well inside the bit.
//
// SDA has separate _i / _o / _oe ports (no inout); sda_pp tells whether the
// current drive is push-pull (read data, T-bit) or open-drain (ACK,
// arbitration, ENTDAA ID).
module dut #(
    parameter logic [47:0] PID         = 48'h14B4_C3D0_1000,
    parameter logic [7:0]  BCR         = 8'h06,     // IBI capable, IBI with Mandatory Data Byte
    parameter logic [7:0]  DCR         = 8'h44,
    parameter logic [6:0]  STATIC_ADDR = 7'h50,     // for SETDASA, 0 = none
    parameter int          NREG        = 16,        // power of two
    parameter int          T_AVAL      = 8          // idle clks before an IBI START request
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       scl_i,
    input  logic       sda_i,
    output logic       sda_o,
    output logic       sda_oe,
    output logic       sda_pp,
    input  logic       ibi_req,
    input  logic [7:0] ibi_mdb,
    output logic       ibi_pending,
    output logic       has_da,
    output logic [6:0] da
);
    localparam int PW = $clog2(NREG);

    localparam logic [3:0] S_IDLE   = 4'd0,
                           S_HDR    = 4'd1,   // address header (7 bits + RnW)
                           S_ACK    = 4'd2,   // we ACK (drive low), then go to nxt
                           S_IBIACK = 4'd3,   // our IBI won: controller ACKs/NACKs
                           S_CCC    = 4'd4,   // CCC code + T
                           S_WR     = 4'd5,   // data byte + T from the controller
                           S_RD     = 4'd6,   // data byte + T to the controller
                           S_DAAID  = 4'd7,   // ENTDAA: 64 bits PID/BCR/DCR, arbitrated
                           S_DAAADR = 4'd8,   // ENTDAA: 7-bit address + parity
                           S_DAAACK = 4'd9,   // ENTDAA: we ACK the address
                           S_IGN    = 4'd10;  // not for us: wait for Sr/P

    localparam logic [1:0] CTX_NONE = 2'd0, CTX_BC = 2'd1, CTX_DIR = 2'd2;

    logic          scl_q, sda_q;
    wire           rise  =  scl_i & ~scl_q;
    wire           fall  = ~scl_i &  scl_q;
    wire           start =  scl_i &  scl_q &  sda_q & ~sda_i;
    wire           stop  =  scl_i &  scl_q & ~sda_q &  sda_i;

    logic [3:0]    st, nxt;
    logic [6:0]    bcnt;
    logic [7:0]    sr;
    logic          arb;        // arbitrating our IBI in this header
    logic          req_drv;    // we pulled SDA low to request a START
    logic [1:0]    ctx;
    logic [7:0]    ccc;
    logic          is_ccc;     // current WR/RD carries a CCC payload (else private)
    logic          ibi_tx;     // current RD is our IBI payload
    logic          entdaa;
    logic [7:0]    nbyte;
    logic [7:0]    regs [NREG];
    logic [PW-1:0] ptr;
    logic          enint, enhj;
    logic [15:0]   mwl;
    logic          perr;
    logic [7:0]    mdb;
    logic [6:0]    new_da;
    logic [7:0]    tx;
    logic          tx_last;
    logic [7:0]    idle_cnt;

    wire  [63:0]   daa_id = {PID, BCR, DCR};
    wire  [7:0]    my_hdr = {da, 1'b1};
    wire  [7:0]    hdr    = {sr[6:0], sda_i};     // valid on the 8th header bit

    // what we send next while reading out, and whether it is the last byte
    logic [7:0] rd_now;
    logic       rd_last_now;
    always_comb begin
        rd_now      = 8'h00;
        rd_last_now = 1'b1;
        if (ibi_tx) begin
            rd_now = mdb;
        end else if (!is_ccc) begin
            rd_now      = regs[ptr];
            rd_last_now = (ptr == PW'(NREG - 1));
        end else begin
            case (ccc)
                8'h8D: begin rd_now = PID[8'(47 - 8 * nbyte) -: 8]; rd_last_now = (nbyte == 8'd5); end
                8'h8E: rd_now = BCR;
                8'h8F: rd_now = DCR;
                8'h8B: begin rd_now = (nbyte == 0) ? mwl[15:8] : mwl[7:0]; rd_last_now = (nbyte == 8'd1); end
                8'h90: begin rd_now = (nbyte == 0) ? 8'h00 : {2'b00, perr, 4'b0000, ibi_pending}; rd_last_now = (nbyte == 8'd1); end
                default: ;
            endcase
        end
    end

    // direct CCCs this target answers, and their direction (1 = GET)
    function automatic logic dir_ok(input logic [7:0] c, input logic rnw);
        case (c)
            8'h80, 8'h81, 8'h89:               return !rnw;
            8'h8B, 8'h8D, 8'h8E, 8'h8F, 8'h90: return rnw;
            default:                           return 1'b0;
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_q <= 1'b1; sda_q <= 1'b1;
            sda_o <= 1'b0; sda_oe <= 1'b0; sda_pp <= 1'b0;
            st <= S_IDLE; nxt <= S_IDLE; bcnt <= '0; sr <= '0;
            arb <= 1'b0; req_drv <= 1'b0; ctx <= CTX_NONE; ccc <= '0;
            is_ccc <= 1'b0; ibi_tx <= 1'b0; entdaa <= 1'b0; nbyte <= '0;
            for (int i = 0; i < NREG; i++) regs[i] <= '0;
            ptr <= '0; enint <= 1'b1; enhj <= 1'b1; mwl <= 16'h0010; perr <= 1'b0;
            mdb <= '0; new_da <= '0; tx <= '0; tx_last <= 1'b0; idle_cnt <= '0;
            ibi_pending <= 1'b0; has_da <= 1'b0; da <= '0;
        end else begin
            scl_q <= scl_i;
            sda_q <= sda_i;
            if (ibi_req) begin
                ibi_pending <= 1'b1;
                mdb         <= ibi_mdb;
            end

            if (stop) begin
                st <= S_IDLE; sda_oe <= 1'b0; sda_pp <= 1'b0;
                ctx <= CTX_NONE; entdaa <= 1'b0; arb <= 1'b0; req_drv <= 1'b0;
                ibi_tx <= 1'b0; idle_cnt <= '0;
            end else if (start) begin
                // arbitration only in the header after a START, never after Sr
                arb    <= (st == S_IDLE) && ibi_pending && enint && has_da && BCR[1];
                st     <= S_HDR;
                bcnt   <= '0;
                ibi_tx <= 1'b0;
                if (st != S_IDLE && ctx == CTX_BC) ctx <= CTX_NONE;   // a broadcast CCC ends at Sr
                if (!req_drv) sda_oe <= 1'b0;   // our own START request: hold SDA low until SCL falls
            end else if (rise) begin
                case (st)
                    S_HDR: begin
                        sr   <= hdr;
                        bcnt <= bcnt + 1'b1;
                        if (arb && my_hdr[3'(7 - bcnt)] && !sda_i) arb <= 1'b0;   // lost
                        if (bcnt == 7'd7) begin
                            bcnt  <= '0;
                            nbyte <= '0;
                            arb   <= 1'b0;
                            if (arb && hdr == my_hdr) begin
                                st <= S_IBIACK;                                  // our IBI won
                            end else if (hdr[7:1] == 7'h7E && !hdr[0]) begin
                                st <= S_ACK; nxt <= S_CCC; ctx <= CTX_NONE; entdaa <= 1'b0;
                            end else if (hdr[7:1] == 7'h7E && hdr[0] && entdaa && !has_da) begin
                                st <= S_ACK; nxt <= S_DAAID;
                            end else if (ctx == CTX_DIR && has_da && hdr[7:1] == da && dir_ok(ccc, hdr[0])) begin
                                st <= S_ACK; nxt <= hdr[0] ? S_RD : S_WR; is_ccc <= 1'b1;
                            end else if (ctx == CTX_DIR && ccc == 8'h87 && !has_da && STATIC_ADDR != 7'h00
                                         && hdr[7:1] == STATIC_ADDR && !hdr[0]) begin
                                st <= S_ACK; nxt <= S_WR; is_ccc <= 1'b1;
                            end else if (ctx != CTX_DIR && has_da && hdr[7:1] == da) begin
                                st <= S_ACK; nxt <= hdr[0] ? S_RD : S_WR; is_ccc <= 1'b0;
                            end else begin
                                st <= S_IGN;
                            end
                        end
                    end
                    S_ACK: begin
                        st   <= nxt;
                        bcnt <= '0;
                    end
                    S_IBIACK: begin
                        if (sda_i) begin
                            st <= S_IGN;                  // NACKed: stays pending
                        end else if (BCR[2]) begin
                            st <= S_RD; ibi_tx <= 1'b1; is_ccc <= 1'b0; nbyte <= '0; bcnt <= '0;
                        end else begin
                            st <= S_IGN; ibi_pending <= 1'b0;
                        end
                    end
                    S_CCC, S_WR: begin
                        if (bcnt < 7'd8) begin
                            sr   <= {sr[6:0], sda_i};
                            bcnt <= bcnt + 1'b1;
                        end else begin                    // T-bit: odd parity
                            bcnt <= '0;
                            if (sda_i != ~^sr) begin
                                perr <= 1'b1;
                                st   <= S_IGN;
                            end else if (st == S_CCC) begin
                                ccc   <= sr;
                                nbyte <= '0;
                                if (sr == 8'h07) begin
                                    entdaa <= 1'b1; st <= S_IGN;
                                end else if (sr == 8'h06) begin
                                    has_da <= 1'b0; st <= S_IGN;
                                end else if (!sr[7]) begin
                                    ctx <= CTX_BC; st <= S_WR; is_ccc <= 1'b1;
                                end else begin
                                    ctx <= CTX_DIR; st <= S_IGN;
                                end
                            end else begin
                                nbyte <= nbyte + 1'b1;
                                if (!is_ccc) begin
                                    if (nbyte == 0) ptr <= sr[PW-1:0];
                                    else begin
                                        regs[ptr] <= sr;
                                        ptr       <= ptr + 1'b1;
                                    end
                                end else begin
                                    case (ccc)
                                        8'h00, 8'h80: begin enint <= enint | sr[0]; enhj <= enhj | sr[3]; end
                                        8'h01, 8'h81: begin enint <= enint & ~sr[0]; enhj <= enhj & ~sr[3]; end
                                        8'h09, 8'h89: begin
                                            if (nbyte == 0)      mwl[15:8] <= sr;
                                            else if (nbyte == 1) mwl[7:0]  <= sr;
                                        end
                                        8'h87: if (nbyte == 0) begin da <= sr[7:1]; has_da <= 1'b1; end
                                        default: ;
                                    endcase
                                end
                            end
                        end
                    end
                    S_RD: begin
                        if (bcnt < 7'd8) begin
                            bcnt <= bcnt + 1'b1;
                        end else begin                    // our T-bit has been read
                            bcnt  <= '0;
                            nbyte <= nbyte + 1'b1;
                            if (!is_ccc && !ibi_tx) ptr <= ptr + 1'b1;
                            if (is_ccc && ccc == 8'h90 && tx_last) perr <= 1'b0;
                            if (ibi_tx && tx_last) ibi_pending <= 1'b0;
                            if (tx_last) st <= S_IGN;     // T=0: hold it until SCL falls
                            else         sda_oe <= 1'b0;  // T=1: hand SDA over (the controller may abort)
                        end
                    end
                    S_DAAID: begin
                        if (daa_id[6'(63 - bcnt)] && !sda_i) st <= S_IGN;       // lost: wait for the next round
                        else if (bcnt == 7'd63) begin st <= S_DAAADR; bcnt <= '0; end
                        else bcnt <= bcnt + 1'b1;
                    end
                    S_DAAADR: begin
                        sr <= {sr[6:0], sda_i};
                        if (bcnt == 7'd7) begin           // parity bit (odd)
                            bcnt <= '0;
                            if (sda_i == ~^sr[6:0]) begin new_da <= sr[6:0]; st <= S_DAAACK; end
                            else st <= S_IGN;             // bad parity: NACK, take part in the next round
                        end else bcnt <= bcnt + 1'b1;
                    end
                    S_DAAACK: begin
                        da <= new_da; has_da <= 1'b1; st <= S_IGN;
                    end
                    default: ;
                endcase
            end else if (fall) begin
                req_drv <= 1'b0;
                case (st)
                    S_HDR: begin
                        sda_pp <= 1'b0;
                        sda_o  <= 1'b0;
                        sda_oe <= arb ? ~my_hdr[3'(7 - bcnt)] : 1'b0;
                    end
                    S_ACK, S_DAAACK: begin
                        sda_oe <= 1'b1; sda_o <= 1'b0; sda_pp <= 1'b0;
                    end
                    S_RD: begin
                        sda_oe <= 1'b1;
                        sda_pp <= 1'b1;
                        if (bcnt == 0) begin
                            tx      <= rd_now;
                            tx_last <= rd_last_now;
                            sda_o   <= rd_now[7];
                        end else if (bcnt < 7'd8) begin
                            sda_o <= tx[3'(7 - bcnt)];
                        end else begin
                            sda_o <= ~tx_last;            // T: 1 = more data, 0 = end of data
                        end
                    end
                    S_DAAID: begin
                        sda_oe <= ~daa_id[6'(63 - bcnt)]; sda_o <= 1'b0; sda_pp <= 1'b0;
                    end
                    default: begin
                        sda_oe <= 1'b0; sda_pp <= 1'b0;
                    end
                endcase
            end else if (st == S_IDLE) begin
                if (scl_i && sda_i) begin
                    if (idle_cnt != 8'hFF) idle_cnt <= idle_cnt + 1'b1;
                end else idle_cnt <= '0;
                if (ibi_pending && enint && has_da && BCR[1] && !req_drv && scl_i && sda_i && idle_cnt >= 8'(T_AVAL)) begin
                    sda_oe <= 1'b1; sda_o <= 1'b0; sda_pp <= 1'b0;   // START request
                    req_drv <= 1'b1;
                end
            end
        end
    end

    initial $display("Hi from DUT: I3C SDR target, PID=%012h BCR=%02h DCR=%02h", PID, BCR, DCR);
endmodule
