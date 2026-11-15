// PMBus device - the RTL side of the pmbus agent's testbench, PMBus 1.3.1
// Part II. Synthesizable; the SMBus message layer (PEC, lengths, ARA,
// timeout, NACK of unsupported codes) is odve_smbus_tgt_eng (smbus agent),
// on odve_i2c_tgt_phy (i2c agent). The same behaviour as the TB model
// odve_pmbus_dev_model:
//   PAGE 00h        0 or 1; other values invalid data
//   OPERATION 01h   per page; accepted when bits [5:4] = 00 and [1:0] = 00
//   ON_OFF_CONFIG   02h per page, bits [7:5] = 0 (default 18h: on/off by OPERATION)
//   CLEAR_FAULTS    03h clears STATUS_CML, releases SMBALERT#
//   CAPABILITY      19h = 90h (PEC, 100 kHz, SMBALERT#), read only
//   VOUT_MODE       20h = 17h (ULINEAR16, exponent -9), writes invalid data
//   VOUT_COMMAND    21h per page, ULINEAR16 (defaults 0200h = 1.0 V, 0333h = 1.6 V)
//   STATUS_BYTE     78h {BUSY=0, OFF, 0000, CML, 0}, STATUS_WORD 79h (+ PG_STATUS# = OFF in bit 11), read only
//   STATUS_CML      7Eh bit 7 command, 6 data, 5 PEC, 1 other; writing 1s clears bits
//   READ_VOUT       8Bh VOUT_COMMAND when on, else 0; READ_IOUT 8Ch LINEAR11 2.5 A / 1.25 A when on, else 0
//   PMBUS_REVISION  98h = 33h
//   output on = !ON_OFF_CONFIG[4] || !ON_OFF_CONFIG[3] || OPERATION[7]
//   every communication fault sets its STATUS_CML bit and asserts SMBALERT#
module dut #(
    parameter logic [6:0]  ADDR    = 7'h40,
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
    output logic alert_o,
    output logic alert_oe
);
    localparam int MAXBLK = 32;

    logic [7:0]  q_cmd, rd_idx, rd_len, rd_data, recv_data, wlen;
    logic [2:0]  q_kind;
    logic        q_wr_ok, q_rd_ok, recv_ok, wr_p, quick_p, quick_rw, ara_done_p, err_p;
    logic [5:0]  err_mask;
    logic [8*(MAXBLK+1)-1:0] wbuf;

    logic        page;
    logic [7:0]  operation     [2];
    logic [7:0]  on_off_config [2];
    logic [15:0] vout_command  [2];
    logic [7:0]  cml;
    logic        alert;

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

    wire        on_p   = !on_off_config[page][4] || !on_off_config[page][3] || operation[page][7];
    wire [7:0]  st_byte = {1'b0, !on_p, 4'b0000, (cml != 8'h00), 1'b0};
    wire [15:0] st_word = {4'b0000, !on_p, 3'b000, st_byte};
    wire [15:0] rd_vout = on_p ? vout_command[page] : 16'h0000;
    wire [15:0] rd_iout = !on_p ? 16'hF000 : (page == 1'b0) ? 16'hF00A : 16'hF005;

    // command set: SMBus transaction type (1 send, 2 byte, 3 word), write / read permission
    always_comb begin
        q_kind  = 3'd0;
        q_wr_ok = 1'b1;
        case (q_cmd)
            8'h00, 8'h01, 8'h02, 8'h20, 8'h7E: q_kind = 3'd2;
            8'h19, 8'h78, 8'h98:               begin q_kind = 3'd2; q_wr_ok = 1'b0; end
            8'h03:                             q_kind = 3'd1;
            8'h21:                             q_kind = 3'd3;
            8'h79, 8'h8B, 8'h8C:               begin q_kind = 3'd3; q_wr_ok = 1'b0; end
            default: ;
        endcase
    end
    assign q_rd_ok   = (q_kind != 3'd1);
    assign recv_ok   = 1'b0;              // a message starting with a read: FFh, CML other (10.9.1)
    assign recv_data = 8'hFF;

    function automatic logic [7:0] lo_hi(input logic [15:0] v, input logic [7:0] i);
        return (i == 8'h00) ? v[7:0] : v[15:8];
    endfunction

    always_comb begin
        rd_len  = 8'd1;
        rd_data = 8'hFF;
        case (q_cmd)
            8'h00: rd_data = {7'h00, page};
            8'h01: rd_data = operation[page];
            8'h02: rd_data = on_off_config[page];
            8'h19: rd_data = 8'h90;
            8'h20: rd_data = 8'h17;
            8'h78: rd_data = st_byte;
            8'h7E: rd_data = cml;
            8'h98: rd_data = 8'h33;
            8'h21: begin rd_len = 8'd2; rd_data = lo_hi(vout_command[page], rd_idx); end
            8'h79: begin rd_len = 8'd2; rd_data = lo_hi(st_word, rd_idx); end
            8'h8B: begin rd_len = 8'd2; rd_data = lo_hi(rd_vout, rd_idx); end
            8'h8C: begin rd_len = 8'd2; rd_data = lo_hi(rd_iout, rd_idx); end
            default: rd_len = 8'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            page <= 1'b0;
            operation[0] <= 8'h00;     operation[1] <= 8'h00;
            on_off_config[0] <= 8'h18; on_off_config[1] <= 8'h18;
            vout_command[0] <= 16'h0200; vout_command[1] <= 16'h0333;
            cml <= 8'h00;
            alert <= 1'b0;
        end else begin
            if (wr_p) begin
                case (q_cmd)
                    8'h00: if (wbuf[7:0] < 8'd2) page <= wbuf[0]; else begin cml[6] <= 1'b1; alert <= 1'b1; end
                    8'h01: if (wbuf[5:4] == 2'b00 && wbuf[1:0] == 2'b00) operation[page] <= wbuf[7:0];
                           else begin cml[6] <= 1'b1; alert <= 1'b1; end
                    8'h02: if (wbuf[7:5] == 3'b000) on_off_config[page] <= wbuf[7:0];
                           else begin cml[6] <= 1'b1; alert <= 1'b1; end
                    8'h20: begin cml[6] <= 1'b1; alert <= 1'b1; end
                    8'h21: vout_command[page] <= wbuf[15:0];
                    8'h7E: cml <= cml & ~wbuf[7:0];
                    8'h03: begin cml <= 8'h00; alert <= 1'b0; end
                    default: ;
                endcase
            end
            if (quick_p && quick_rw) begin cml[1] <= 1'b1; alert <= 1'b1; end
            if (ara_done_p) alert <= 1'b0;
            if (err_p) begin
                alert <= 1'b1;
                if (err_mask[1]) cml[7] <= 1'b1;
                if (err_mask[2]) cml[6] <= 1'b1;
                if (err_mask[3]) cml[5] <= 1'b1;
                if (err_mask[4] || err_mask[5]) cml[1] <= 1'b1;
            end
        end
    end
endmodule
