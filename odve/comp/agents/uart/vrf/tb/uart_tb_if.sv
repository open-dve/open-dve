// Testbench-only side band of the RTL echo device (vrf/dut/dut.sv): its
// configuration pins, written by the env (env.set_format), and its error
// status pulses, watched by the scoreboard.
interface uart_tb_if (
    input logic clk,
    input logic rst_n
);
    logic [5:0]  lcr;       // 16550 LCR[5:0]
    logic [15:0] div;       // clocks per 16x tick
    logic        afe;       // auto flow control
    logic        st_valid;
    logic        st_oe;
    logic        st_pe;
    logic        st_fe;
    logic        st_bi;
    logic [3:0]  rx_level;
endinterface
