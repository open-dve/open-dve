// Small quad-SPI serial NOR flash, plain synthesizable RTL (instruction set
// after the Winbond W25Q32FV datasheet, scaled down - see doc/spec.md):
//   MEM_BYTES (8 KiB: two 4 KiB sectors, 32 pages of 256 bytes), erased = FFh;
//   SPI mode: 06 04 05 35 31 9F 03 0B 3B BB 6B EB 02 32 20 5A 38
//   QPI mode: 06 04 05 35 31 9F 0B EB 02 20 FF        (0Bh/EBh: 2 dummy clocks)
//   status 1 = {6'b0, WEL, BUSY}, status 2 = {6'b0, QE, 1'b0}
//   6Bh/EBh/32h/38h need QE; while BUSY only 05h/35h are taken;
//   PP/QPP/SE/WRSR2 need WEL, run as a self-timed operation (BUSY) and clear
//   WEL at its end: program = one byte per cycle (old & new) over the 256-byte
//   page buffer, erase = one byte per cycle over the sector, each padded to
//   TPP / TSE / TW cycles. PP/QPP execute only when cs_n rises on a byte
//   boundary, SE/WRSR2 only after exactly their bits.
// The SPI lines are oversampled on clk through two-flop synchronizers, so
// sclk's half period must be >= 4 clk cycles. Data in on rising, out on
// falling sclk edges (modes 0 and 3 alike). io is split into io_i / io_o /
// io_oe - no tristates in here.
module dut #(
    parameter int          MEM_BYTES = 8192,
    parameter int          TPP       = 1500,
    parameter int          TSE       = 5000,
    parameter int          TW        = 200,
    parameter logic [7:0]  MFR_ID    = 8'hEF,
    parameter logic [7:0]  TYPE_SPI  = 8'h40,
    parameter logic [7:0]  TYPE_QPI  = 8'h60,
    parameter logic [7:0]  CAP_ID    = 8'h0D
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       sclk,
    input  logic       cs_n,
    input  logic [3:0] io_i,
    output logic [3:0] io_o,
    output logic [3:0] io_oe
);
    localparam int AW = $clog2(MEM_BYTES);

    typedef struct packed {
        logic       valid;
        logic       needs_qe;
        logic [2:0] al;        // address lanes, 0 = none
        logic [3:0] mc;        // mode clocks
        logic [3:0] dc;        // dummy clocks
        logic [2:0] dl;        // data lanes, 0 = none
        logic       dout;
    } fmt_t;

    function automatic fmt_t decode(input logic [7:0] c, input logic q);
        fmt_t f;
        f = '{valid: 1'b1, needs_qe: 1'b0, al: 3'd0, mc: 4'd0, dc: 4'd0, dl: 3'd0, dout: 1'b0};
        if (!q) begin
            case (c)
                8'h06, 8'h04:        ;
                8'h38:               f.needs_qe = 1'b1;
                8'h05, 8'h35, 8'h9F: begin f.dl = 3'd1; f.dout = 1'b1; end
                8'h31:               f.dl = 3'd1;
                8'h03:               begin f.al = 3'd1; f.dl = 3'd1; f.dout = 1'b1; end
                8'h0B, 8'h5A:        begin f.al = 3'd1; f.dc = 4'd8; f.dl = 3'd1; f.dout = 1'b1; end
                8'h3B:               begin f.al = 3'd1; f.dc = 4'd8; f.dl = 3'd2; f.dout = 1'b1; end
                8'hBB:               begin f.al = 3'd2; f.mc = 4'd4; f.dl = 3'd2; f.dout = 1'b1; end
                8'h6B:               begin f.al = 3'd1; f.dc = 4'd8; f.dl = 3'd4; f.dout = 1'b1; f.needs_qe = 1'b1; end
                8'hEB:               begin f.al = 3'd4; f.mc = 4'd2; f.dc = 4'd4; f.dl = 3'd4; f.dout = 1'b1; f.needs_qe = 1'b1; end
                8'h02:               begin f.al = 3'd1; f.dl = 3'd1; end
                8'h32:               begin f.al = 3'd1; f.dl = 3'd4; f.needs_qe = 1'b1; end
                8'h20:               f.al = 3'd1;
                default:             f.valid = 1'b0;
            endcase
        end else begin
            case (c)
                8'h06, 8'h04, 8'hFF: ;
                8'h05, 8'h35, 8'h9F: begin f.dl = 3'd4; f.dout = 1'b1; end
                8'h31:               f.dl = 3'd4;
                8'h0B:               begin f.al = 3'd4; f.dc = 4'd2; f.dl = 3'd4; f.dout = 1'b1; end
                8'hEB:               begin f.al = 3'd4; f.mc = 4'd2; f.dl = 3'd4; f.dout = 1'b1; end
                8'h02:               begin f.al = 3'd4; f.dl = 3'd4; end
                8'h20:               f.al = 3'd4;
                default:             f.valid = 1'b0;
            endcase
        end
        return f;
    endfunction

    function automatic logic [7:0] sfdp(input logic [7:0] a);
        logic [31:0] bm1;
        bm1 = 32'(MEM_BYTES) * 32'd8 - 32'd1;
        case (a)
            8'h00: return 8'h53;  8'h01: return 8'h46;  8'h02: return 8'h44;  8'h03: return 8'h50;
            8'h04: return 8'h06;  8'h05: return 8'h01;  8'h06: return 8'h00;  8'h07: return 8'hFF;
            8'h08: return 8'h00;  8'h09: return 8'h06;  8'h0A: return 8'h01;  8'h0B: return 8'h09;
            8'h0C: return 8'h80;  8'h0D: return 8'h00;  8'h0E: return 8'h00;  8'h0F: return 8'hFF;
            8'h84: return bm1[7:0];   8'h85: return bm1[15:8];
            8'h86: return bm1[23:16]; 8'h87: return bm1[31:24];
            default: return 8'hFF;
        endcase
    endfunction

    // array and page buffer
    logic [7:0]  mem  [MEM_BYTES];
    logic [7:0]  pbuf [256];
    logic [255:0] pval;
    initial for (int i = 0; i < MEM_BYTES; i++) mem[i] = 8'hFF;

    // synchronizers
    logic [2:0]  sclk_q, cs_q;
    logic [3:0]  io_q1, io_q2;
    wire  sclk_s = sclk_q[1], sclk_d = sclk_q[2];
    wire  cs_s   = cs_q[1],   cs_d   = cs_q[2];
    wire  active = !cs_s;
    wire  start  = active && cs_d;
    wire  stop   = !active && !cs_d;
    wire  rise   = active && !cs_d && sclk_s && !sclk_d;
    wire  fall   = active && !cs_d && !sclk_s && sclk_d;

    // device state
    logic        wel, qe, qpi;
    typedef enum logic [1:0] { OP_NONE, OP_PROG, OP_ERASE, OP_WRSR } op_e;
    op_e         op;
    logic [15:0] op_cnt;
    logic [AW-1:0] op_base;
    wire         busy = (op != OP_NONE);

    // frame state
    logic [15:0] rcnt;
    logic [7:0]  cmd;
    fmt_t        f;
    logic        acc;
    logic [5:0]  a_end, m_end, hdr;
    logic [23:0] addr;
    logic [7:0]  sh;
    logic [3:0]  shn;
    logic [15:0] nb;            // data bytes received
    logic [7:0]  wr1;           // first data byte (WRSR2)
    logic [7:0]  obuf;          // byte being sent
    logic [15:0] obi;           // index of the byte being sent
    logic [1:0]  idm3;          // obi mod 3 (JEDEC ID)

    wire [5:0] cmd_clks = qpi ? 6'd2 : 6'd8;
    wire [7:0] cmd_n    = qpi ? {cmd[3:0], io_q2} : {cmd[6:0], io_q2[0]};
    wire fmt_t f_n      = decode(cmd_n, qpi);
    wire [3:0] lane_in  = (f.dl == 3'd4) ? io_q2 : (f.dl == 3'd2) ? {2'b0, io_q2[1:0]} : {3'b0, io_q2[0]};
    wire [3:0] alane_in = (f.al == 3'd4) ? io_q2 : (f.al == 3'd2) ? {2'b0, io_q2[1:0]} : {3'b0, io_q2[0]};
    wire [3:0] cpb      = (f.dl == 3'd4) ? 4'd2 : (f.dl == 3'd2) ? 4'd4 : 4'd8;   // clocks per byte
    wire [15:0] dclk    = rcnt - 16'(hdr);                                           // data clock index
    // write data: the byte the current rising edge completes
    wire [7:0] byte_n   = (f.dl == 3'd4) ? {sh[3:0], lane_in} : (f.dl == 3'd2) ? {sh[5:0], lane_in[1:0]} : {sh[6:0], lane_in[0]};
    wire       din      = rise && rcnt >= 16'(cmd_clks) && rcnt >= 16'(hdr) && acc && f.dl != 3'd0 && !f.dout;
    wire       din_done = din && (shn + 4'(f.dl) == 4'd8);

    // byte `obi` of the current read-type command
    function automatic logic [7:0] out_byte(input logic [15:0] i, input logic [1:0] m3);
        case (cmd)
            8'h05:   return {6'b0, wel, busy};
            8'h35:   return {6'b0, qe, 1'b0};
            8'h9F:   return (m3 == 2'd0) ? MFR_ID : (m3 == 2'd1) ? (qpi ? TYPE_QPI : TYPE_SPI) : CAP_ID;
            8'h5A:   return sfdp(8'(addr[7:0] + i[7:0]));
            default: return mem[AW'(addr + 24'(i))];
        endcase
    endfunction

    always_ff @(posedge clk) begin
        // self-timed program / erase, one byte per cycle
        if (op == OP_PROG && op_cnt < 16'd256 && pval[op_cnt[7:0]])
            mem[op_base | AW'(op_cnt[7:0])] <= mem[op_base | AW'(op_cnt[7:0])] & pbuf[op_cnt[7:0]];
        if (op == OP_ERASE && op_cnt < 16'd4096)
            mem[op_base | AW'(op_cnt[11:0])] <= 8'hFF;
        // page buffer
        if (din_done && (cmd == 8'h02 || cmd == 8'h32))
            pbuf[8'(addr[7:0] + nb[7:0])] <= byte_n;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_q <= '0; cs_q <= '1; io_q1 <= '1; io_q2 <= '1;
            wel <= 1'b0; qe <= 1'b0; qpi <= 1'b0;
            op <= OP_NONE; op_cnt <= '0; op_base <= '0;
            rcnt <= '0; cmd <= '0; f <= '0; acc <= 1'b0; a_end <= '0; m_end <= '0; hdr <= '0;
            addr <= '0; sh <= '0; shn <= '0; nb <= '0; wr1 <= '0; obuf <= '0; obi <= '0; idm3 <= '0;
            pval <= '0;
            io_o <= '1; io_oe <= '0;
        end else begin
            sclk_q <= {sclk_q[1:0], sclk};
            cs_q   <= {cs_q[1:0], cs_n};
            io_q1  <= io_i;
            io_q2  <= io_q1;

            // self-timed operation
            if (busy) begin
                if (op_cnt == ((op == OP_PROG) ? 16'(TPP) : (op == OP_ERASE) ? 16'(TSE) : 16'(TW))) begin
                    op  <= OP_NONE;
                    wel <= 1'b0;
                end else op_cnt <= op_cnt + 16'd1;
                if (op == OP_PROG && op_cnt < 16'd256) pval[op_cnt[7:0]] <= 1'b0;
            end

            if (!active) io_oe <= '0;

            if (start) begin
                rcnt <= '0; cmd <= '0; acc <= 1'b0; f <= '0;
                addr <= '0; sh <= '0; shn <= '0; nb <= '0; obi <= '0; idm3 <= '0;
                a_end <= cmd_clks; m_end <= cmd_clks; hdr <= cmd_clks;
            end else if (rise) begin
                rcnt <= rcnt + 16'd1;
                if (rcnt < 16'(cmd_clks)) begin
                    cmd <= cmd_n;
                    if (rcnt == 16'(cmd_clks) - 16'd1) begin
                        f     <= f_n;
                        a_end <= cmd_clks + ((f_n.al == 3'd4) ? 6'd6 : (f_n.al == 3'd2) ? 6'd12 : (f_n.al == 3'd1) ? 6'd24 : 6'd0);
                        m_end <= cmd_clks + ((f_n.al == 3'd4) ? 6'd6 : (f_n.al == 3'd2) ? 6'd12 : (f_n.al == 3'd1) ? 6'd24 : 6'd0) + 6'(f_n.mc);
                        hdr   <= cmd_clks + ((f_n.al == 3'd4) ? 6'd6 : (f_n.al == 3'd2) ? 6'd12 : (f_n.al == 3'd1) ? 6'd24 : 6'd0) + 6'(f_n.mc) + 6'(f_n.dc);
                        acc   <= f_n.valid && (!busy || cmd_n == 8'h05 || cmd_n == 8'h35) && (!f_n.needs_qe || qe);
                        if (f_n.valid && !busy && (cmd_n == 8'h02 || cmd_n == 8'h32)) pval <= '0;
                    end
                end else if (rcnt < 16'(a_end)) begin
                    addr <= (f.al == 3'd4) ? {addr[19:0], alane_in} : (f.al == 3'd2) ? {addr[21:0], alane_in[1:0]} : {addr[22:0], alane_in[0]};
                end else if (din) begin
                    if (din_done) begin
                        if (nb == '0) wr1 <= byte_n;
                        if (cmd == 8'h02 || cmd == 8'h32) pval[8'(addr[7:0] + nb[7:0])] <= 1'b1;
                        nb  <= nb + 16'd1;
                        sh  <= '0;
                        shn <= '0;
                    end else begin
                        sh  <= byte_n;
                        shn <= shn + 4'(f.dl);
                    end
                end
            end else if (fall) begin
                if (acc && f.dout && rcnt >= 16'(hdr)) begin
                    logic [7:0] b;
                    if (dclk % 16'(cpb) == 16'd0) begin           // a new byte, MSB group first
                        b    = out_byte(obi, idm3);
                        obi  <= obi + 16'd1;
                        idm3 <= (idm3 == 2'd2) ? 2'd0 : idm3 + 2'd1;
                    end else b = obuf << f.dl;                    // the next group
                    obuf <= b;
                    case (f.dl)
                        3'd4:    begin io_o <= b[7:4];             io_oe <= 4'hF; end
                        3'd2:    begin io_o <= {2'b11, b[7:6]};     io_oe <= 4'h3; end
                        default: begin io_o <= {2'b11, b[7], 1'b1}; io_oe <= 4'h2; end
                    endcase
                end
            end

            // cs_n rose: execute
            if (stop && acc) begin
                case (cmd)
                    8'h06: wel <= 1'b1;
                    8'h04: wel <= 1'b0;
                    8'h38: qpi <= 1'b1;
                    8'hFF: qpi <= 1'b0;
                    8'h31: if (wel && rcnt == 16'(hdr) + 16'(cpb) && shn == '0) begin
                        qe <= wr1[1];
                        op <= OP_WRSR; op_cnt <= '0;
                    end
                    8'h02, 8'h32: if (wel && rcnt > 16'(hdr) && shn == '0) begin
                        op <= OP_PROG; op_cnt <= '0;
                        op_base <= AW'(addr) & ~AW'(255);
                    end
                    8'h20: if (wel && rcnt == 16'(hdr)) begin
                        op <= OP_ERASE; op_cnt <= '0;
                        op_base <= AW'(addr) & ~AW'(4095);
                    end
                    default: ;
                endcase
                acc <= 1'b0;
            end
        end
    end

    initial $display("Hi from DUT: QSPI NOR flash, %0d bytes, JEDEC ID %02h %02h %02h", MEM_BYTES, MFR_ID, TYPE_SPI, CAP_ID);
endmodule
