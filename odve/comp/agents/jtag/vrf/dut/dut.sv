// JTAG target used to exercise the agent: NTAP jtag_tap instances in a
// daisy chain, TDI -> tap[0] -> tap[1] -> ... -> TDO. TAP k has IDCODE
// 32'h1234_5679 + k * 32'h1000_0000 and sees pins_i = 8'hA5 + k. The bus
// TDO enable is the last TAP's. state_o is tap[0]'s TAP state (debug).
module dut #(parameter int NTAP = 1) (
    input  logic            tck,
    input  logic            tms,
    input  logic            tdi,
    input  logic            trst_n,
    input  logic            por_n,
    output logic            tdo,
    output logic            tdo_oe,
    output logic [NTAP*8-1:0] pins_o,
    output logic [3:0]      state_o
);
    logic [NTAP:0]   chain;
    logic [NTAP-1:0] oe;
    logic [3:0]      st [NTAP];

    assign chain[0] = tdi;

    for (genvar k = 0; k < NTAP; k++) begin : g_tap
        jtag_tap #(.IDCODE(32'h1234_5679 + k * 32'h1000_0000)) tap_i (
            .tck     (tck),
            .tms     (tms),
            .tdi     (chain[k]),
            .trst_n  (trst_n),
            .por_n   (por_n),
            .tdo     (chain[k+1]),
            .tdo_oe  (oe[k]),
            .pins_i  (8'hA5 + 8'(k)),
            .pins_o  (pins_o[k*8 +: 8]),
            .state_o (st[k])
        );
    end

    assign tdo     = chain[NTAP];
    assign tdo_oe  = oe[NTAP-1];
    assign state_o = st[0];

    initial $display("Hi from DUT: JTAG chain of %0d TAP(s)", NTAP);
endmodule
