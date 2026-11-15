// SMBus target message layer, synthesizable, on top of odve_i2c_tgt_phy
// (i2c agent). Shared by the smbus and pmbus DUTs; the device's command set
// lives in the module that instantiates it. Same rules as the TB model
// odve_smbus_dev_model (src/agent/odve_smbus_dev_model.sv):
//   * address ADDR (7-bit); while alert_i is set also the Alert Response
//     Address 0001 100 (read): answers {ADDR, 0}, then ara_done_p once that
//     byte has been read (SMBus 3.3 A.2)
//   * the first written byte is the command code; q_kind (from the device,
//     for q_cmd) gives its protocols: unsupported -> NACK (ERR_CMD); a data
//     byte to a code with !q_wr_ok -> NACK (ERR_CMD); block byte count above
//     MAXBLK -> NACK (ERR_DATA)
//   * PEC: CRC-8 x^8+x^2+x+1 over every byte from the START (6.4); the byte
//     after a full write message is accepted as PEC when the CRC becomes 0,
//     otherwise NACKed (ERR_PEC); further bytes NACKed (ERR_DATA)
//   * a write message is handed to the device (wr_p) at STOP when complete
//     and error free; shorter messages are dropped
//   * reads: after Sr the device's response bytes (rd_len, rd_data at
//     rd_idx), then the PEC, then FFh (past the PEC: ERR_OTHER); a read right
//     after START is Receive Byte (recv_data) or, when no byte was clocked
//     out, Quick Command read; a write of no byte is Quick Command write
//   * clock-low timeout (TMO_CYC): ERR_TMO; START/STOP inside a byte: ERR_OTHER
//   * errors are reported once per message, at its end (err_p + err_mask)
module odve_smbus_tgt_eng #(
    parameter logic [6:0]  ADDR    = 7'h3A,
    parameter int unsigned TMO_CYC = 600,
    parameter int unsigned MAXBLK  = 32
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         scl_i,
    input  logic         sda_i,
    output logic         scl_oe,
    output logic         sda_oe,
    // command decode, combinational in the device
    output logic [7:0]   q_cmd,
    input  logic [2:0]   q_kind,      // odve_smbus_cmd_e: 0 none, 1 send, 2 byte, 3 word, 4 pcall, 5 block, 6 bpcall
    input  logic         q_wr_ok,
    input  logic         q_rd_ok,
    // the bytes written after the command (count included), byte i at [8*i +: 8]
    output logic [8*(MAXBLK+1)-1:0] wbuf,
    output logic [7:0]   wlen,
    // a complete write message
    output logic         wr_p,
    // read response, combinational in the device
    output logic [7:0]   rd_idx,
    input  logic [7:0]   rd_len,
    input  logic [7:0]   rd_data,
    input  logic [7:0]   recv_data,
    input  logic         recv_ok,
    // other end-of-message events
    output logic         quick_p,
    output logic         quick_rw,
    output logic         ara_done_p,
    output logic         err_p,
    output logic [5:0]   err_mask,    // bit 1 CMD, 2 DATA, 3 PEC, 4 OTHER, 5 TMO
    input  logic         alert_i
);
    localparam logic [6:0] ARA = 7'h0C;
    localparam int ERR_CMD = 1, ERR_DATA = 2, ERR_PEC = 3, ERR_OTHER = 4, ERR_TMO = 5;

    logic       start_p, restart, stop_p, abort_p, tmo_p, rx_p, rx_first, tx_p, mack_p, mack;
    logic [7:0] rx_data, tx_data;
    logic       rx_ack, rx_tx;

    odve_i2c_tgt_phy #(.TMO_CYC(TMO_CYC)) phy (
        .clk, .rst_n, .scl_i, .sda_i, .scl_oe, .sda_oe,
        .start_p, .restart, .stop_p, .abort_p, .tmo_p,
        .rx_p, .rx_data, .rx_first, .rx_ack, .rx_tx,
        .tx_p, .tx_data, .mack_p, .mack,
        .stretch_cyc(8'h00)
    );

    function automatic logic [7:0] crc8(input logic [7:0] c, input logic [7:0] d);
        logic [7:0] x;
        x = c ^ d;
        for (int i = 0; i < 8; i++) x = x[7] ? ({x[6:0], 1'b0} ^ 8'h07) : {x[6:0], 1'b0};
        return x;
    endfunction

    logic [7:0] crc, cmd, wcnt, rcnt, ntx, rsp_len;
    logic [8:0] exp_len;          // bytes after the command; exp_known = 0 until a block count
    logic       exp_known, cmd_valid, bad, rd_start, ara, rd_seg, rsp_recv, addressed, msg_restart;
    logic [2:0] kind;
    logic [5:0] errs;

    assign q_cmd  = (rx_p && rx_first == 1'b0 && wcnt == 8'h00) ? rx_data : cmd;
    assign rd_idx = rcnt;

    wire [7:0] nc     = crc8(crc, rx_data);
    wire [7:0] j      = wcnt - 8'h01;
    wire [7:0] tx_byte = ara      ? ((rcnt == 8'h00) ? {ADDR, 1'b0} : (rcnt == 8'h01) ? crc : 8'hFF)
                       : rsp_recv ? ((rcnt == 8'h00) ? recv_data    : (rcnt == 8'h01) ? crc : 8'hFF)
                       : (rcnt < rsp_len) ? rd_data : (rcnt == rsp_len) ? crc : 8'hFF;

    function automatic logic [8:0] len_of(input logic [2:0] k);
        case (k)
            3'd1:       return 9'd0;
            3'd2:       return 9'd1;
            3'd3, 3'd4: return 9'd2;
            default:    return 9'd0;
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc <= 8'h00; cmd <= 8'h00; wcnt <= 8'h00; rcnt <= 8'h00; ntx <= 8'h00; rsp_len <= 8'h00;
            exp_len <= 9'h0; exp_known <= 1'b0; cmd_valid <= 1'b0; bad <= 1'b0; rd_start <= 1'b0;
            ara <= 1'b0; rd_seg <= 1'b0; rsp_recv <= 1'b0; addressed <= 1'b0; msg_restart <= 1'b0;
            kind <= 3'd0; errs <= 6'h0; wbuf <= '0; wlen <= 8'h00;
            rx_ack <= 1'b0; rx_tx <= 1'b0; tx_data <= 8'hFF;
            wr_p <= 1'b0; quick_p <= 1'b0; quick_rw <= 1'b0; ara_done_p <= 1'b0; err_p <= 1'b0; err_mask <= 6'h0;
        end else begin
            wr_p <= 1'b0; quick_p <= 1'b0; ara_done_p <= 1'b0; err_p <= 1'b0;

            // ---- end of a message: STOP, timeout, or START inside a byte
            if (addressed && (stop_p || tmo_p || (start_p && abort_p))) begin
                logic [5:0] e;
                e = errs;
                addressed <= 1'b0;
                if (tmo_p)        e[ERR_TMO] = 1'b1;
                else if (abort_p) e[ERR_OTHER] = 1'b1;
                else if (ara) begin
                    if (ntx != 8'h00) ara_done_p <= 1'b1;
                end else if (rd_start) begin
                    if (ntx == 8'h00) begin quick_p <= 1'b1; quick_rw <= 1'b1; end
                    else if (!recv_ok) e[ERR_OTHER] = 1'b1;
                end else if (!rd_seg) begin
                    if (wcnt == 8'h00) begin quick_p <= 1'b1; quick_rw <= 1'b0; end
                    else if (!bad && cmd_valid && exp_known && ({1'b0, j} == exp_len || {1'b0, j} == exp_len + 9'd1))
                        wr_p <= 1'b1;
                end
                err_mask <= e;
                err_p    <= (e != 6'h0);
            end
            if (start_p) msg_restart <= restart;

            // ---- received bytes
            if (rx_p) begin
                rx_ack <= 1'b0;
                rx_tx  <= 1'b0;
                if (rx_first) begin
                    if (!msg_restart) begin
                        // a new message
                        crc <= crc8(8'h00, rx_data);
                        wcnt <= 8'h00; ntx <= 8'h00; errs <= 6'h0; bad <= 1'b0; cmd_valid <= 1'b0;
                        exp_len <= 9'h0; exp_known <= 1'b0; wlen <= 8'h00;
                        rd_start <= rx_data[0];
                        ara <= (rx_data[7:1] == ARA);
                        rsp_recv <= 1'b1;
                        if (rx_data[7:1] == ADDR || (rx_data[7:1] == ARA && rx_data[0] && alert_i)) begin
                            rx_ack <= 1'b1; rx_tx <= rx_data[0]; addressed <= 1'b1;
                        end else begin
                            addressed <= 1'b0;
                        end
                    end else begin
                        crc <= nc;
                        if (addressed && rx_data[7:1] == ADDR) begin
                            rx_ack <= 1'b1; rx_tx <= rx_data[0];
                            rsp_recv <= !cmd_valid;
                            if (rx_data[0] && cmd_valid && !q_rd_ok) begin
                                errs[ERR_CMD] <= 1'b1; bad <= 1'b1;
                            end
                        end else begin
                            addressed <= 1'b0;
                        end
                    end
                    rd_seg <= rx_data[0];
                    rcnt <= 8'h00;
                    ntx <= 8'h00;
                    rsp_len <= (rx_data[0] && msg_restart && cmd_valid && q_rd_ok) ? rd_len : 8'h00;
                end else if (addressed && !rd_seg) begin
                    crc <= nc;
                    wcnt <= wcnt + 8'h01;
                    if (wcnt == 8'h00) begin
                        cmd  <= rx_data;
                        kind <= q_kind;
                        if (q_kind == 3'd0) begin
                            errs[ERR_CMD] <= 1'b1; bad <= 1'b1;
                        end else begin
                            rx_ack <= 1'b1;
                            cmd_valid <= 1'b1;
                            exp_len <= len_of(q_kind);
                            exp_known <= !(q_kind == 3'd5 || q_kind == 3'd6);
                        end
                    end else if (bad) begin
                        // NACK the rest
                    end else if (j == 8'h00 && kind != 3'd1 && !q_wr_ok) begin
                        errs[ERR_CMD] <= 1'b1; bad <= 1'b1;
                    end else if (j == 8'h00 && !exp_known) begin
                        if (rx_data > 8'(MAXBLK)) begin
                            errs[ERR_DATA] <= 1'b1; bad <= 1'b1;
                        end else begin
                            rx_ack <= 1'b1;
                            exp_len <= 9'd1 + {1'b0, rx_data};
                            exp_known <= 1'b1;
                            wbuf[7:0] <= rx_data;
                            wlen <= 8'h01;
                        end
                    end else if ({1'b0, j} < exp_len) begin
                        rx_ack <= 1'b1;
                        wbuf[8*j +: 8] <= rx_data;
                        wlen <= j + 8'h01;
                    end else if ({1'b0, j} == exp_len) begin
                        if (nc == 8'h00) rx_ack <= 1'b1;
                        else begin errs[ERR_PEC] <= 1'b1; bad <= 1'b1; end
                    end else begin
                        errs[ERR_DATA] <= 1'b1; bad <= 1'b1;
                    end
                end
            end

            // ---- transmitted bytes
            if (tx_p) begin
                tx_data <= tx_byte;
                crc     <= crc8(crc, tx_byte);
                rcnt    <= rcnt + 8'h01;
                if (!ara && !rsp_recv && rcnt > rsp_len) errs[ERR_OTHER] <= 1'b1;
                if ((ara || rsp_recv) && rcnt > 8'h01) errs[ERR_OTHER] <= 1'b1;
            end
            if (mack_p) ntx <= ntx + 8'h01;
        end
    end
endmodule
