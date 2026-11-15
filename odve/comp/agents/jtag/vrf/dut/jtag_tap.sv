// One IEEE 1149.1 TAP, synthesizable RTL.
//   TAP controller: 16 states, advanced by TMS at the rising TCK edge,
//                   asynchronous reset to Test-Logic-Reset by TRST_n or POR
//   IR (4 bits):    Capture-IR loads 0001, shifts LSB first at rising TCK,
//                   Update-IR latches at the falling edge; Test-Logic-Reset
//                   selects IDCODE
//   instructions:   EXTEST 0000, SAMPLE/PRELOAD 0001, IDCODE 0010,
//                   USERDATA 1000, BYPASS 1111 (every other code = BYPASS)
//   data registers: boundary 8 bits (captures pins_i, Update latches bsr_upd,
//                   driven on pins_o under EXTEST), IDCODE 32 bits,
//                   USERDATA 32 bits read/write, BYPASS 1 bit (captures 0)
//   TDO:            changes at the falling TCK edge, enabled (tdo_oe) only
//                   in Shift-IR/Shift-DR
// TRST_n/POR clear USERDATA and the boundary update latch; Test-Logic-Reset
// through TMS does not.
module jtag_tap #(
    parameter logic [31:0] IDCODE = 32'h1234_5679   // bit 0 must be 1
) (
    input  logic       tck,
    input  logic       tms,
    input  logic       tdi,
    input  logic       trst_n,
    input  logic       por_n,
    output logic       tdo,
    output logic       tdo_oe,
    input  logic [7:0] pins_i,
    output logic [7:0] pins_o,
    output logic [3:0] state_o
);
    localparam logic [3:0] S_TLR = 4'd0,  S_RTI = 4'd1,
                           S_SEL_DR = 4'd2,  S_CAP_DR = 4'd3,  S_SH_DR = 4'd4,  S_EX1_DR = 4'd5,
                           S_PA_DR  = 4'd6,  S_EX2_DR = 4'd7,  S_UPD_DR = 4'd8,
                           S_SEL_IR = 4'd9,  S_CAP_IR = 4'd10, S_SH_IR = 4'd11, S_EX1_IR = 4'd12,
                           S_PA_IR  = 4'd13, S_EX2_IR = 4'd14, S_UPD_IR = 4'd15;
    localparam logic [3:0] I_EXTEST = 4'h0, I_SAMPLE = 4'h1, I_IDCODE = 4'h2, I_USER = 4'h8;

    wire arst_n = trst_n & por_n;

    logic [3:0]  state, nstate;
    logic [3:0]  ir_sr, ir;
    logic [31:0] dr_sr;
    logic [31:0] user;
    logic [7:0]  bsr_upd;

    always_comb begin
        case (state)
            S_TLR:    nstate = tms ? S_TLR    : S_RTI;
            S_RTI:    nstate = tms ? S_SEL_DR : S_RTI;
            S_SEL_DR: nstate = tms ? S_SEL_IR : S_CAP_DR;
            S_CAP_DR: nstate = tms ? S_EX1_DR : S_SH_DR;
            S_SH_DR:  nstate = tms ? S_EX1_DR : S_SH_DR;
            S_EX1_DR: nstate = tms ? S_UPD_DR : S_PA_DR;
            S_PA_DR:  nstate = tms ? S_EX2_DR : S_PA_DR;
            S_EX2_DR: nstate = tms ? S_UPD_DR : S_SH_DR;
            S_UPD_DR: nstate = tms ? S_SEL_DR : S_RTI;
            S_SEL_IR: nstate = tms ? S_TLR    : S_CAP_IR;
            S_CAP_IR: nstate = tms ? S_EX1_IR : S_SH_IR;
            S_SH_IR:  nstate = tms ? S_EX1_IR : S_SH_IR;
            S_EX1_IR: nstate = tms ? S_UPD_IR : S_PA_IR;
            S_PA_IR:  nstate = tms ? S_EX2_IR : S_PA_IR;
            S_EX2_IR: nstate = tms ? S_UPD_IR : S_SH_IR;
            default:  nstate = tms ? S_SEL_DR : S_RTI;     // S_UPD_IR
        endcase
    end

    // rising TCK: state, capture, shift
    always_ff @(posedge tck or negedge arst_n) begin
        if (!arst_n) begin
            state <= S_TLR;
            ir_sr <= 4'b0001;
            dr_sr <= '0;
        end else begin
            state <= nstate;
            case (state)
                S_CAP_IR: ir_sr <= 4'b0001;
                S_SH_IR:  ir_sr <= {tdi, ir_sr[3:1]};
                S_CAP_DR: case (ir)
                    I_EXTEST, I_SAMPLE: dr_sr <= {24'h0, pins_i};
                    I_IDCODE:           dr_sr <= IDCODE;
                    I_USER:             dr_sr <= user;
                    default:            dr_sr <= '0;            // BYPASS
                endcase
                S_SH_DR: case (ir)
                    I_EXTEST, I_SAMPLE: dr_sr[7:0]  <= {tdi, dr_sr[7:1]};
                    I_IDCODE, I_USER:   dr_sr       <= {tdi, dr_sr[31:1]};
                    default:            dr_sr[0]    <= tdi;     // BYPASS: one stage
                endcase
                default: ;
            endcase
        end
    end

    // falling TCK: instruction and data updates, TDO
    always_ff @(negedge tck or negedge arst_n) begin
        if (!arst_n) begin
            ir      <= I_IDCODE;
            user    <= '0;
            bsr_upd <= '0;
            tdo     <= 1'b0;
            tdo_oe  <= 1'b0;
        end else begin
            if (state == S_TLR)         ir <= I_IDCODE;
            else if (state == S_UPD_IR) ir <= ir_sr;
            if (state == S_UPD_DR) begin
                if (ir == I_USER)                          user    <= dr_sr;
                if (ir == I_EXTEST || ir == I_SAMPLE)      bsr_upd <= dr_sr[7:0];
            end
            tdo_oe <= (state == S_SH_IR) || (state == S_SH_DR);
            tdo    <= (state == S_SH_IR) ? ir_sr[0] : (state == S_SH_DR) ? dr_sr[0] : 1'b0;
        end
    end

    assign pins_o  = (ir == I_EXTEST) ? bsr_upd : 8'h00;
    assign state_o = state;
endmodule
