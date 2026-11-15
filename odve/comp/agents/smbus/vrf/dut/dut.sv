// SMBus device - the RTL side of the smbus agent's testbench. Synthesizable;
// the message layer (PEC, lengths, ARA, Quick Command, timeout) is
// odve_smbus_tgt_eng, this module holds the command set (the same as the TB
// model odve_smbus_ref_model):
//   00h-07h  byte registers (Write/Read Byte)
//   10h-13h  word registers (Write/Read Word)
//   20h      Process Call: returns the written word inverted
//   30h      block register, up to 32 bytes (Block Write/Read)
//   31h      Block Write-Block Read Process Call: returns the written bytes inverted
//   40h      Send Byte CLEAR_STATUS: clears STATUS[4:0], releases SMBALERT#
//   41h      Send Byte SET_ALERT: sets STATUS[2], asserts SMBALERT#
//   Receive Byte returns STATUS = {READY=1, 00, TMO, QUICK, ALERT_REQ, CMD_ERR, PEC_ERR}
//   Quick Command: STATUS.QUICK = R/W#
//   unsupported command / invalid data -> CMD_ERR + SMBALERT#, wrong PEC ->
//   PEC_ERR + SMBALERT#, clock-low timeout -> TMO; the ARA read releases SMBALERT#.
module dut #(
    parameter logic [6:0]  ADDR    = 7'h3A,
    parameter int unsigned TMO_CYC = 600
) (
    input  logic clk,
    input  logic rst_n,
    input  logic scl_i,
    input  logic sda_i,
    output logic scl_o,
    output logic scl_oe,
    output logic sda_o,
    output logic sda_oe,
    output logic alert_o,     // SMBALERT#, open drain: pulls low when alert_oe
    output logic alert_oe
);
    localparam int MAXBLK = 32;

    logic [7:0]  q_cmd, rd_idx, rd_len, rd_data, recv_data, wlen;
    logic [2:0]  q_kind;
    logic        q_wr_ok, q_rd_ok, recv_ok, wr_p, quick_p, quick_rw, ara_done_p, err_p;
    logic [5:0]  err_mask;
    logic [8*(MAXBLK+1)-1:0] wbuf;

    logic [7:0]  bregs [8];
    logic [15:0] wregs [4];
    logic [7:0]  blk   [MAXBLK];
    logic [7:0]  blk_len;
    logic        st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err, alert;

    assign scl_o    = 1'b0;
    assign sda_o    = 1'b0;
    assign alert_o  = 1'b0;
    assign alert_oe = alert;

    odve_smbus_tgt_eng #(.ADDR(ADDR), .TMO_CYC(TMO_CYC), .MAXBLK(MAXBLK)) eng (
        .clk, .rst_n, .scl_i, .sda_i, .scl_oe, .sda_oe,
        .q_cmd, .q_kind, .q_wr_ok, .q_rd_ok, .wbuf, .wlen, .wr_p,
        .rd_idx, .rd_len, .rd_data, .recv_data, .recv_ok,
        .quick_p, .quick_rw, .ara_done_p, .err_p, .err_mask, .alert_i(alert)
    );

    function automatic logic [2:0] kind_of(input logic [7:0] c);
        if (c <= 8'h07)               return 3'd2;
        if (c >= 8'h10 && c <= 8'h13) return 3'd3;
        if (c == 8'h20)               return 3'd4;
        if (c == 8'h30)               return 3'd5;
        if (c == 8'h31)               return 3'd6;
        if (c == 8'h40 || c == 8'h41) return 3'd1;
        return 3'd0;
    endfunction

    function automatic logic [7:0] wb(input logic [7:0] i);
        return (i < wlen) ? wbuf[8*i +: 8] : 8'h00;
    endfunction

    wire [2:0] ckind = kind_of(q_cmd);
    assign q_kind    = ckind;
    assign q_wr_ok   = 1'b1;
    assign q_rd_ok   = (ckind != 3'd1);
    assign recv_ok   = 1'b1;
    assign recv_data = {1'b1, 2'b00, st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err};

    // read response: length and byte rd_idx for command q_cmd
    always_comb begin
        rd_len  = 8'h00;
        rd_data = 8'hFF;
        case (ckind)
            3'd2: begin rd_len = 8'd1; rd_data = bregs[q_cmd[2:0]]; end
            3'd3: begin rd_len = 8'd2; rd_data = (rd_idx == 8'h00) ? wregs[q_cmd[1:0]][7:0] : wregs[q_cmd[1:0]][15:8]; end
            3'd4: begin rd_len = 8'd2; rd_data = ~wb(rd_idx); end
            3'd5: begin
                rd_len  = blk_len + 8'd1;
                rd_data = (rd_idx == 8'h00) ? blk_len : blk[5'(rd_idx - 8'h01)];
            end
            3'd6: begin
                rd_len  = (wlen != 8'h00) ? wlen : 8'h01;
                rd_data = (rd_idx == 8'h00) ? ((wlen != 8'h00) ? wlen - 8'h01 : 8'h00) : ~wb(rd_idx);
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) bregs[i] <= 8'h00;
            for (int i = 0; i < 4; i++) wregs[i] <= 16'h0000;
            for (int i = 0; i < MAXBLK; i++) blk[i] <= 8'h00;
            blk_len <= 8'h00;
            {st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err, alert} <= '0;
        end else begin
            if (wr_p) begin
                case (ckind)
                    3'd2: bregs[q_cmd[2:0]] <= wbuf[7:0];
                    3'd3: wregs[q_cmd[1:0]] <= wbuf[15:0];
                    3'd5: begin
                        blk_len <= wbuf[7:0];
                        for (int i = 0; i < MAXBLK; i++) blk[i] <= wbuf[8*(i+1) +: 8];
                    end
                    3'd1: begin
                        if (q_cmd == 8'h40) begin
                            {st_tmo, st_quick, st_alert_req, st_cmd_err, st_pec_err, alert} <= '0;
                        end else begin
                            st_alert_req <= 1'b1;
                            alert <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end
            if (quick_p) st_quick <= quick_rw;
            if (ara_done_p) alert <= 1'b0;
            if (err_p) begin
                if (err_mask[1] || err_mask[2]) begin st_cmd_err <= 1'b1; alert <= 1'b1; end
                if (err_mask[3])                begin st_pec_err <= 1'b1; alert <= 1'b1; end
                if (err_mask[5])                st_tmo <= 1'b1;
            end
        end
    end
endmodule
